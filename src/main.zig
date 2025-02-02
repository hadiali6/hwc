const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.main);
const heap = std.heap;

const wlr = @import("wlroots");

const hwc = @import("hwc");
const api = @import("api.zig");

pub fn main() !void {
    defer {
        if (builtin.mode == .Debug) {
            api.scene.dump(&hwc.server.surface_manager.wlr_scene.tree.node);
        }

        hwc.server.deinit();
    }

    api.process.setup();
    wlr.log.init(.info, null);
    try hwc.server.init(heap.c_allocator);
    try hwc.server.startSocket();
    try config();
    try hwc.server.start();
}

// for testing...
fn config() !void {
    // try api.process.spawn("hello-wayland");
    try api.process.spawn("foot 2> /dev/null");
    // try api.process.spawn("~/code/hwc-client/zig-out/bin/hwc-client");

    _ = try hwc.server.wl_server.getEventLoop().addIdle(?*anyopaque, struct {
        fn callback(_: ?*anyopaque) void {
            _ = api.output.create(&hwc.server, 1920, 1080) catch |err| {
                log.err("{s} failed: '{}'", .{ @src().fn_name, err });
            };
        }
    }.callback, null);
}

test "server" {
    const os = std.os;
    const posix = std.posix;
    const testing = std.testing;

    const test_helpers = struct {
        fn handleKillTimer(_: ?*anyopaque) c_int {
            const pid = os.linux.getpid();
            posix.kill(pid, posix.SIG.TERM) catch |err| {
                log.err("{s}: failed: '{}' pid='{}' sig='SIGTERM'", .{ @src().fn_name, err, pid });
                posix.exit(1);
            };

            return 0;
        }
    };

    defer {
        if (builtin.mode == .Debug) {
            api.scene.dump(&hwc.server.surface_manager.wlr_scene.tree.node);
        }

        hwc.server.deinit();
    }

    testing.log_level = .debug;
    api.process.setup();
    wlr.log.init(.info, null);
    try hwc.server.init(testing.allocator);
    try hwc.server.startSocket();
    try config();

    {
        const wl_event_loop = hwc.server.wl_server.getEventLoop();
        const source = try wl_event_loop.addTimer(?*anyopaque, test_helpers.handleKillTimer, null);
        _ = try source.timerUpdate(100);
    }

    try hwc.server.start();
}
