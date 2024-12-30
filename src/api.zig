const std = @import("std");
const c = std.c;
const debug = std.debug;
const fs = std.fs;
const log = std.log.scoped(.api);
const mem = std.mem;
const os = std.os;
const posix = std.posix;

const fd_t = posix.fd_t;
const pid_t = posix.pid_t;

const wlr = @import("wlroots");

const hwc = @import("hwc.zig");
const util = @import("util.zig");

const server = &@import("root").server;

var original_rlimit: ?posix.rlimit = null;

pub fn processSetup() void {
    // Ignore SIGPIPE so we don't get killed when writing to a socket that
    // has had its read end closed by another process.
    const sig_ign = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.PIPE, &sig_ign, null) catch unreachable;

    // Most unix systems have a default limit of 1024 file descriptors and it
    // seems unlikely for this default to be universally raised due to the
    // broken behavior of select() on fds with value >1024. However, it is
    // unreasonable to use such a low limit for a process such as river which
    // uses many fds in its communication with wayland clients and the kernel.
    //
    // There is however an advantage to having a relatively low limit: it helps
    // to catch any fd leaks. Therefore, don't use some crazy high limit that
    // can never be reached before the system runs out of memory. This can be
    // raised further if anyone reaches it in practice.
    if (posix.getrlimit(.NOFILE)) |original| {
        original_rlimit = original;
        const new: posix.rlimit = .{
            .cur = @min(4096, original.max),
            .max = original.max,
        };
        if (posix.setrlimit(.NOFILE, new)) {
            log.info("raised file descriptor limit of the compositor process to {d}", .{new.cur});
        } else |_| {
            log.err("setrlimit failed, using system default file descriptor limit of {d}", .{
                original.cur,
            });
        }
    } else |_| {
        log.err("getrlimit failed, using system default file descriptor limit ", .{});
    }
}

fn cleanupChild() void {
    if (os.linux.setsid() < 0) unreachable;
    if (posix.system.sigprocmask(posix.SIG.SETMASK, &posix.empty_sigset, null) < 0) unreachable;

    const sig_dfl = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.PIPE, &sig_dfl, null) catch unreachable;

    if (original_rlimit) |original| {
        posix.setrlimit(.NOFILE, original) catch {
            std.log.err("failed to restore original file descriptor limit for " ++
                "child process, setrlimit failed", .{});
        };
    }
}

pub fn spawn(cmd: []const u8) !void {
    const child_args = [_:null]?[*:0]u8{
        @constCast(@ptrCast("/bin/sh")),
        @constCast(@ptrCast("-c")),
        @constCast(@ptrCast(cmd)),
    };

    const child_pid = try posix.fork();

    if (child_pid == 0) {
        cleanupChild();

        const grandchild_pid = posix.fork() catch posix.system._exit(1);

        if (grandchild_pid == 0) {
            posix.execveZ("/bin/sh", &child_args, c.environ) catch
                posix.system._exit(1);
        } else {
            posix.system._exit(0);
        }
    } else {
        // Wait the intermediate child.
        const ret = posix.waitpid(child_pid, 0);

        if (!posix.W.IFEXITED(ret.status) or
            (posix.W.IFEXITED(ret.status) and posix.W.EXITSTATUS(ret.status) != 0))
        {
            log.err("fork failed", .{});
            return;
        }
    }
}

pub fn pipedSpawn(cmd: []const u8) !pid_t {
    const child_args = [_:null]?[*:0]u8{
        @constCast(@ptrCast("/bin/sh")),
        @constCast(@ptrCast("-c")),
        @constCast(@ptrCast(cmd)),
    };

    const pid_pipe_fd: [2]fd_t = try posix.pipe();

    const child_pid = try posix.fork();

    if (child_pid == 0) {
        posix.close(pid_pipe_fd[0]);

        cleanupChild();

        const grandchild_pid = posix.fork() catch posix.system._exit(1);

        if (grandchild_pid == 0) {
            posix.close(pid_pipe_fd[1]);
            posix.execveZ("/bin/sh", &child_args, c.environ) catch
                posix.system._exit(1);
        } else {
            _ = posix.write(pid_pipe_fd[1], mem.asBytes(&grandchild_pid)) catch {
                log.err("write failed", .{});
                return 0;
            };
            posix.close(pid_pipe_fd[1]);
            posix.system._exit(0);
        }
    } else {
        posix.close(pid_pipe_fd[1]);
        // Wait the intermediate child.
        const ret = posix.waitpid(child_pid, 0);

        if (!posix.W.IFEXITED(ret.status) or
            (posix.W.IFEXITED(ret.status) and posix.W.EXITSTATUS(ret.status) != 0))
        {
            log.err("fork failed", .{});
            return 0;
        }

        var grandchild_pid: pid_t = undefined;
        const bytes_read = try posix.read(pid_pipe_fd[0], mem.asBytes(&grandchild_pid));

        posix.close(pid_pipe_fd[0]);
        debug.assert(bytes_read == @sizeOf(pid_t));

        return grandchild_pid;
    }
}

pub const ProcessResult = struct {
    pid: pid_t,
    stdin_fd: fd_t,
    stdout_fd: fd_t,
    stderr_fd: fd_t,
};

pub fn pipedSpawnWithStreams(cmd: []const u8) !ProcessResult {
    const child_args = [_:null]?[*:0]u8{
        @constCast(@ptrCast("/bin/sh")),
        @constCast(@ptrCast("-c")),
        @constCast(@ptrCast(cmd)),
    };

    var info: ProcessResult = .{
        .pid = -1,
        .stdin_fd = -1,
        .stdout_fd = -1,
        .stderr_fd = -1,
    };

    const pid_pipe_fd: [2]fd_t = try posix.pipe();
    const stdin_pipe_fd: [2]fd_t = try posix.pipe();
    const stdout_pipe_fd: [2]fd_t = try posix.pipe();
    const stderr_pipe_fd: [2]fd_t = try posix.pipe();

    const child_pid = try posix.fork();

    if (child_pid == 0) {
        posix.close(pid_pipe_fd[0]);

        cleanupChild();

        const grandchild_pid = posix.fork() catch posix.system._exit(1);

        if (grandchild_pid == 0) {
            posix.close(pid_pipe_fd[1]);

            posix.dup2(stdin_pipe_fd[0], posix.STDIN_FILENO) catch posix.system._exit(1);
            posix.dup2(stdout_pipe_fd[1], posix.STDOUT_FILENO) catch posix.system._exit(1);
            posix.dup2(stderr_pipe_fd[1], posix.STDERR_FILENO) catch posix.system._exit(1);

            posix.close(stdin_pipe_fd[0]);
            posix.close(stdin_pipe_fd[1]);
            posix.close(stdout_pipe_fd[0]);
            posix.close(stdout_pipe_fd[1]);
            posix.close(stderr_pipe_fd[0]);
            posix.close(stderr_pipe_fd[1]);

            posix.execveZ("/bin/sh", &child_args, c.environ) catch
                posix.system._exit(1);
        } else {
            // Close the unused pipe ends in the child process
            posix.close(stdin_pipe_fd[0]);
            posix.close(stdout_pipe_fd[1]);
            posix.close(stderr_pipe_fd[1]);

            _ = posix.write(pid_pipe_fd[1], mem.asBytes(&grandchild_pid)) catch {
                posix.system._exit(1);
            };
            posix.close(pid_pipe_fd[1]);
            posix.system._exit(0);
        }
    } else {
        posix.close(pid_pipe_fd[1]);
        // Wait the intermediate child.
        const ret = posix.waitpid(child_pid, 0);

        if (!posix.W.IFEXITED(ret.status) or
            (posix.W.IFEXITED(ret.status) and posix.W.EXITSTATUS(ret.status) != 0))
        {
            log.err("fork failed", .{});
            return error.Unexpected;
        }

        const bytes_read = try posix.read(pid_pipe_fd[0], mem.asBytes(&info.pid));

        posix.close(pid_pipe_fd[0]);
        debug.assert(bytes_read == @sizeOf(pid_t));

        info.stdin_fd = stdin_pipe_fd[1];
        info.stdout_fd = stdout_pipe_fd[0];
        info.stderr_fd = stderr_pipe_fd[0];

        posix.close(stdin_pipe_fd[0]);
        posix.close(stdout_pipe_fd[1]);
        posix.close(stderr_pipe_fd[1]);

        return info;
    }
}

pub fn createKeyboardGroup() !*hwc.input.KeyboardGroup {
    const keyboard_group = try util.allocator.create(hwc.input.KeyboardGroup);
    errdefer keyboard_group.deinit();

    return keyboard_group;
}

pub fn findSeat(id: []const u8) ?*hwc.input.Seat {
    var iterator = server.input_manager.seats.iterator(.forward);
    while (iterator.next()) |seat| {
        if (mem.eql(u8, id, mem.sliceTo(seat.wlr_seat.name, 0))) {
            return seat;
        }
    }

    return null;
}

pub fn findKeyboardGroup(seat: *hwc.input.Seat, id: []const u8) ?*hwc.input.KeyboardGroup {
    var iterator = seat.keyboard_groups.iterator(.forward);
    while (iterator.next()) |keyboard_group| {
        if (mem.eql(u8, id, keyboard_group.identifier)) {
            return keyboard_group;
        }
    }

    return null;
}

const Data = struct {
    const Self = @This();

    status: union(enum) {
        fail,
        success: *wlr.Output,
    },
    width: c_uint,
    height: c_uint,

    fn processBackend(backend: *wlr.Backend, data: ?*anyopaque) callconv(.C) void {
        const result: *Self = if (data) |d|
            @alignCast(@ptrCast(d))
        else
            unreachable;

        if (backend.isWl()) {
            const wlr_output = backend.wlOuputCreate() catch {
                result.status = .fail;
                return;
            };

            result.status = .{ .success = wlr_output };
        } else if (backend.isHeadless()) {
            const wlr_output = backend.headlessAddOutput(result.width, result.height) catch {
                result.status = .fail;
                return;
            };

            result.status = .{ .success = wlr_output };
        } else if (wlr.config.has_x11_backend) {
            if (backend.isX11()) {
                const wlr_output = backend.x11OutputCreate() catch {
                    result.status = .fail;
                    return;
                };

                result.status = .{ .success = wlr_output };
            }
        }
    }
};

pub fn createOutput(width: c_uint, height: c_uint) !*wlr.Output {
    debug.assert(server.backend.isMulti());

    var result = Data{
        .status = undefined,
        .width = width,
        .height = height,
    };

    server.backend.multiForEachBackend(Data.processBackend, &result);

    if (result.status == .fail) {
        log.err("output can only be created on Wayland, X11, and headless backends", .{});
        return error.CreateOutputFailed;
    }

    return result.status.success;
}
