const std = @import("std");
const log = std.log.scoped(.config);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc.zig");
const util = @import("util.zig");

decoration_mode: wlr.XdgToplevelDecorationV1.Mode,
keyboard_repeat_rate: u31,
keyboard_repeat_delay: u31,
keybinds: std.ArrayListUnmanaged(hwc.input.Keybind),

pub fn init(self: *hwc.Config) !void {
    self.* = .{
        .decoration_mode = .client_side,
        .keyboard_repeat_rate = 50,
        .keyboard_repeat_delay = 300,
        .keybinds = try std.ArrayListUnmanaged(hwc.input.Keybind).initCapacity(util.allocator, 10),
    };
}

pub fn deinit(self: *hwc.Config) void {
    self.keybinds.deinit(util.allocator);
}
