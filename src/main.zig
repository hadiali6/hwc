const std = @import("std");
const log = std.log.scoped(.main);
const heap = std.heap;

const wlr = @import("wlroots");

const hwc = @import("hwc");
const api = @import("api.zig");

pub fn main() !void {
    api.process.setup();
    wlr.log.init(.info, null);
    try hwc.server.init(heap.c_allocator);
    try hwc.server.startSocket();
    try config();
    try hwc.server.start();
    hwc.server.deinit();
}

// for testing...
fn config() !void {
    try api.process.spawn("hello-wayland");
    try api.process.spawn("foot 2> /dev/null");
    try api.process.spawn("~/code/hwc-client/zig-out/bin/hwc-client");

    _ = try hwc.server.wl_server.getEventLoop().addIdle(
        ?*anyopaque,
        struct {
            fn callback(_: ?*anyopaque) void {
                _ = api.output.createOutput(&hwc.server, 1920, 1080) catch |err| {
                    log.err("{s} failed: '{}'", .{ @src().fn_name, err });
                };
            }
        }.callback,
        null,
    );
}

test {
    api.process.setup();
    wlr.log.init(.info, null);
    try hwc.server.init(std.testing.allocator);
    try hwc.server.startSocket();
    try config();
    const source = try hwc.server.wl_server.getEventLoop().addTimer(?*anyopaque, struct {
        fn w(_: ?*anyopaque) c_int {
            std.posix.kill(std.os.linux.getpid(), std.posix.SIG.TERM) catch {};
            return 0;
        }
    }.w, null);
    _ = try source.timerUpdate(100);
    try hwc.server.start();
    hwc.server.deinit();
}
