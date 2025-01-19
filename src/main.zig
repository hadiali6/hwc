const std = @import("std");

pub const Server = @import("Server.zig");

const api = @import("api.zig");

pub var server: Server = undefined;

pub fn main() !void {
    defer server.deinit();

    api.setupProcess();

    try server.init(std.heap.c_allocator);
    try server.start();

    server.wl_server.run();
}
