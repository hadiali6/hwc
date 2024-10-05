const std = @import("std");
const log = std.log.scoped(.xdgdecoration);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const config = @import("config.zig");
const hwc = @import("hwc.zig");

const server = &@import("root").server;

wlr_xdg_decoration: *wlr.XdgToplevelDecorationV1,

request_mode: wl.Listener(*wlr.XdgToplevelDecorationV1) =
    wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleSetDecorationMode),
destroy: wl.Listener(*wlr.XdgToplevelDecorationV1) =
    wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleDestroy),

pub fn init(wlr_xdg_decoration: *wlr.XdgToplevelDecorationV1) void {
    const toplevel: *hwc.XdgToplevel = @ptrFromInt(wlr_xdg_decoration.toplevel.base.data);

    toplevel.decoration = .{ .wlr_xdg_decoration = wlr_xdg_decoration };

    const decoration = &toplevel.decoration.?;

    wlr_xdg_decoration.events.request_mode.add(&decoration.request_mode);
    wlr_xdg_decoration.events.destroy.add(&decoration.destroy);
}

fn handleSetDecorationMode(
    listener: *wl.Listener(*wlr.XdgToplevelDecorationV1),
    _: *wlr.XdgToplevelDecorationV1,
) void {
    const decoration: *hwc.XdgDecoration = @fieldParentPtr("request_mode", listener);
    _ = decoration.wlr_xdg_decoration.setMode(config.decoration_mode);
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.XdgToplevelDecorationV1),
    _: *wlr.XdgToplevelDecorationV1,
) void {
    const decoration: *hwc.XdgDecoration = @fieldParentPtr("destroy", listener);
    const toplevel: *hwc.XdgToplevel = @ptrFromInt(decoration.wlr_xdg_decoration.toplevel.base.data);

    decoration.request_mode.link.remove();
    decoration.destroy.link.remove();

    toplevel.decoration = null;
}
