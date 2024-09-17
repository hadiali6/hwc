const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

pub const decoration_mode: wlr.XdgToplevelDecorationV1.Mode = .client_side;
pub const keyboard_rate: u32 = 50;
pub const keyboard_delay: u32 = 300;
