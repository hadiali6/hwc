const std = @import("std");

const wlr = @import("wlroots");

pub const Output = @import("Output.zig");
pub const Server = @import("Server.zig");
pub const XdgPopup = @import("XdgPopup.zig");
pub const XdgToplevel = @import("XdgToplevel.zig");

const api = @import("api.zig");

pub var server: Server = undefined;

pub fn main() !void {
    defer server.deinit();

    api.setupProcess();

    wlr.log.init(.info, null);

    try server.init(std.heap.c_allocator);
    try server.start();

    try api.spawn("hello-wayland");

    server.wl_server.run();
}
