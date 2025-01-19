const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

wlr_output_layout: *wlr.OutputLayout,

pub fn init() !void {}
pub fn deinit() void {}
