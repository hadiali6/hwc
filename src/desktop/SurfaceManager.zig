const std = @import("std");
const log = std.log.scoped(.@"desktop.SurfaceManager");
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

wlr_xdg_shell: *wlr.XdgShell,
new_toplevel: wl.Listener(*wlr.XdgToplevel) = wl.Listener(*wlr.XdgToplevel).init(handleNewToplevel),
toplevels: wl.list.Head(hwc.desktop.XdgToplevel, .link),

wlr_layer_shell: *wlr.LayerShellV1,
new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1) =
    wl.Listener(*wlr.LayerSurfaceV1).init(handleNewLayerSurface),

// TODO: create/use wlr.ForeignToplevelHandleV1
wlr_foreign_toplevel_manager: *wlr.ForeignToplevelManagerV1,

pub fn init(self: *hwc.desktop.SurfaceManager) !void {
    self.* = .{
        .wlr_xdg_shell = try wlr.XdgShell.create(server.wl_server, 6),
        .wlr_layer_shell = try wlr.LayerShellV1.create(server.wl_server, 4),
        .wlr_foreign_toplevel_manager = try wlr.ForeignToplevelManagerV1.create(server.wl_server),
        .toplevels = undefined,
    };

    self.toplevels.init();

    self.wlr_xdg_shell.events.new_toplevel.add(&self.new_toplevel);
    self.wlr_layer_shell.events.new_surface.add(&self.new_layer_surface);

    log.info("{s}", .{@src().fn_name});
}

pub fn deinit(self: *hwc.desktop.SurfaceManager) void {
    self.new_toplevel.link.remove();
    self.new_layer_surface.link.remove();
    assert(self.toplevels.empty());

    log.info("{s}", .{@src().fn_name});
}

fn handleNewToplevel(
    listener: *wl.Listener(*wlr.XdgToplevel),
    wlr_xdg_toplevel: *wlr.XdgToplevel,
) void {
    const surface_manager: *hwc.desktop.SurfaceManager = @fieldParentPtr("new_toplevel", listener);

    const toplevel = hwc.desktop.XdgToplevel.create(
        server.allocator,
        wlr_xdg_toplevel,
    ) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });

        if (err == error.OutOfMemory) {
            wlr_xdg_toplevel.resource.postNoMemory();
        }

        return;
    };

    surface_manager.toplevels.prepend(toplevel);
}

fn handleNewLayerSurface(
    _: *wl.Listener(*wlr.LayerSurfaceV1),
    wlr_layer_surface: *wlr.LayerSurfaceV1,
) void {
    hwc.desktop.LayerSurface.create(server.allocator, wlr_layer_surface) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });

        if (err == error.OutOfMemory) {
            wlr_layer_surface.resource.postNoMemory();
        }
    };
}
