const std = @import("std");
const log = std.log.scoped(.main);
const heap = std.heap;

const wlr = @import("wlroots");

pub const Server = @import("Server.zig");

pub const desktop = struct {
    pub const LayerSurface = @import("desktop/LayerSurface.zig");
    pub const Output = @import("desktop/Output.zig");
    pub const OutputManager = @import("desktop/OutputManager.zig");
    pub const SurfaceManager = @import("desktop/SurfaceManager.zig");
    pub const XdgPopup = @import("desktop/XdgPopup.zig");
    pub const XdgToplevel = @import("desktop/XdgToplevel.zig");
};

pub const input = struct {
    pub const Device = @import("input/Device.zig");
    pub const Manager = @import("input/Manager.zig");
    pub const Seat = @import("input/Seat.zig");
};

const api = @import("api.zig");

pub var server: Server = undefined;

pub fn main() !void {
    api.setupProcess();
    wlr.log.init(.info, null);
    try server.init(heap.c_allocator);
    try server.startSocket();
    try api.spawn("hello-wayland");
    try server.start();
    server.deinit();
}
