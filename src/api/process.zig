const std = @import("std");
const setup_log = std.log.scoped(.@"api.process.setup");
const spawn_log = std.log.scoped(.@"api.process.spawn");
const posix = std.posix;
const os = std.os;
const c = std.c;

var original_rlimit: ?posix.rlimit = null;

pub fn setup() void {
    const sig_ignore = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.PIPE, &sig_ignore, null) catch unreachable;

    const original = posix.getrlimit(.NOFILE) catch |err| {
        setup_log.err(
            "{s}: '{}': getrlimit failed, using system default file descriptor limit",
            .{ @src().fn_name, err },
        );
        return;
    };

    setup_log.info("{s}: system default file descriptor limit: soft -> {d}, hard -> {d}", .{
        @src().fn_name,
        original.cur,
        original.max,
    });

    original_rlimit = original;

    const new = posix.rlimit{
        .cur = @min(4096, original.max),
        .max = original.max,
    };

    posix.setrlimit(.NOFILE, new) catch |err| {
        setup_log.err("{s}: '{}': setrlimit failed, using system default file descriptor limit", .{
            @src().fn_name,
            err,
        });
        return;
    };

    setup_log.info("{s}: new file descriptor limit: soft -> {d}, hard -> {d}", .{
        @src().fn_name,
        new.cur,
        new.max,
    });
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
            posix.execveZ("/bin/sh", &child_args, c.environ) catch posix.system._exit(1);
        } else {
            spawn_log.info("{s}: pid='{}'", .{ @src().fn_name, grandchild_pid });
            posix.system._exit(0);
        }
    } else {
        // wait the intermediate child
        const wait_pid_status = posix.waitpid(child_pid, 0).status;

        if (!posix.W.IFEXITED(wait_pid_status) or
            (posix.W.IFEXITED(wait_pid_status) and posix.W.EXITSTATUS(wait_pid_status) != 0))
        {
            spawn_log.err("{s}: fork/execve failed", .{@src().fn_name});
            return error.Other;
        }
    }
}

fn cleanupChild() void {
    if (os.linux.setsid() < 0) {
        unreachable;
    }

    if (posix.system.sigprocmask(posix.SIG.SETMASK, &posix.empty_sigset, null) < 0) {
        unreachable;
    }

    const sig_default = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = posix.empty_sigset,
        .flags = 0,
    };
    posix.sigaction(posix.SIG.PIPE, &sig_default, null) catch unreachable;

    if (original_rlimit) |original| {
        posix.setrlimit(.NOFILE, original) catch |err| {
            spawn_log.err(
                "{s} failed: '{}': " ++
                    "setrlimit unable to restore original file descriptor limit for child process",
                .{ @src().fn_name, err },
            );
        };
    }
}
