const std = @import("std");
const log = std.log.scoped(.XdgToplevel);
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

wlr_xdg_toplevel: *wlr.XdgToplevel,
surface_tree: *wlr.SceneTree,
popup_tree: *wlr.SceneTree,

// listeners that are always active over the toplevel's lifetime
destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),
map: wl.Listener(void) = wl.Listener(void).init(handleMap),
unmap: wl.Listener(void) = wl.Listener(void).init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

// listeners that are only active while the toplevel is mapped
ack_configure: wl.Listener(*wlr.XdgSurface.Configure) =
    wl.Listener(*wlr.XdgSurface.Configure).init(handleAckConfigure),
request_fullscreen: wl.Listener(void) = wl.Listener(void).init(handleRequestFullscreen),
request_maximize: wl.Listener(void) = wl.Listener(void).init(handleRequestMaximize),
request_minimize: wl.Listener(void) = wl.Listener(void).init(handleRequestMinimize),
request_move: wl.Listener(*wlr.XdgToplevel.event.Move) =
    wl.Listener(*wlr.XdgToplevel.event.Move).init(handleRequestMove),
request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) =
    wl.Listener(*wlr.XdgToplevel.event.Resize).init(handleRequestResize),
set_title: wl.Listener(void) = wl.Listener(void).init(handleSetTitle),
set_app_id: wl.Listener(void) = wl.Listener(void).init(handleSetAppId),

pub fn create(allocator: mem.Allocator, wlr_xdg_toplevel: *wlr.XdgToplevel) !void {
    const toplevel = try allocator.create(hwc.XdgToplevel);
    errdefer allocator.destroy(toplevel);

    const surface_tree = try server.wlr_scene.tree.createSceneTree();
    errdefer surface_tree.node.destroy();

    // TODO: use current outputs popup layer
    const popup_tree = try server.wlr_scene.tree.createSceneTree();
    errdefer popup_tree.node.destroy();

    toplevel.* = .{
        .wlr_xdg_toplevel = wlr_xdg_toplevel,
        .surface_tree = surface_tree,
        .popup_tree = popup_tree,
    };

    wlr_xdg_toplevel.base.surface.events.unmap.add(&toplevel.unmap);
    errdefer toplevel.unmap.link.remove();

    _ = try toplevel.surface_tree.createSceneXdgSurface(wlr_xdg_toplevel.base);

    // add listeners that are active over the toplevel's entire lifetime
    wlr_xdg_toplevel.events.destroy.add(&toplevel.destroy);
    wlr_xdg_toplevel.base.surface.events.map.add(&toplevel.map);
    wlr_xdg_toplevel.base.surface.events.commit.add(&toplevel.commit);
    wlr_xdg_toplevel.base.events.new_popup.add(&toplevel.new_popup);
}

fn destroyPopups(self: *hwc.XdgToplevel) void {
    var it = self.wlr_xdg_toplevel.base.popups.safeIterator(.forward);
    while (it.next()) |wlr_xdg_popup| {
        wlr_xdg_popup.destroy();
    }
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("destroy", listener);

    toplevel.destroyPopups();

    toplevel.surface_tree.node.destroy();
    toplevel.popup_tree.node.destroy();

    toplevel.destroy.link.remove();
    toplevel.map.link.remove();
    toplevel.unmap.link.remove();
    toplevel.commit.link.remove();
    toplevel.new_popup.link.remove();

    server.allocator.destroy(toplevel);
}

fn handleMap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("map", listener);
    _ = toplevel.wlr_xdg_toplevel.setActivated(true);

    // add listeners that are only active while mapped
    toplevel.wlr_xdg_toplevel.base.events.ack_configure.add(&toplevel.ack_configure);
    toplevel.wlr_xdg_toplevel.events.request_fullscreen.add(&toplevel.request_fullscreen);
    toplevel.wlr_xdg_toplevel.events.request_maximize.add(&toplevel.request_maximize);
    toplevel.wlr_xdg_toplevel.events.request_minimize.add(&toplevel.request_minimize);
    toplevel.wlr_xdg_toplevel.events.request_move.add(&toplevel.request_move);
    toplevel.wlr_xdg_toplevel.events.request_resize.add(&toplevel.request_resize);
    toplevel.wlr_xdg_toplevel.events.set_title.add(&toplevel.set_title);
    toplevel.wlr_xdg_toplevel.events.set_app_id.add(&toplevel.set_app_id);
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("unmap", listener);
    _ = toplevel.wlr_xdg_toplevel.setActivated(false);

    // remove listeners that are only active while mapped
    toplevel.ack_configure.link.remove();
    toplevel.request_fullscreen.link.remove();
    toplevel.request_maximize.link.remove();
    toplevel.request_minimize.link.remove();
    toplevel.request_move.link.remove();
    toplevel.request_resize.link.remove();
    toplevel.set_title.link.remove();
    toplevel.set_app_id.link.remove();
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("commit", listener);

    if (toplevel.wlr_xdg_toplevel.base.initial_commit) {
        _ = toplevel.wlr_xdg_toplevel.setSize(0, 0);
    }
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("new_popup", listener);

    hwc.XdgPopup.create(
        server.allocator,
        wlr_xdg_popup,
        toplevel.popup_tree,
        toplevel.popup_tree,
    ) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        wlr_xdg_popup.resource.postNoMemory();
    };
}

fn handleAckConfigure(
    listener: *wl.Listener(*wlr.XdgSurface.Configure),
    event: *wlr.XdgSurface.Configure,
) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("ack_configure", listener);
    _ = toplevel;
    _ = event;
}

fn handleRequestFullscreen(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_fullscreen", listener);
    _ = toplevel;
}

fn handleRequestMaximize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_maximize", listener);
    _ = toplevel;
}

fn handleRequestMinimize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_minimize", listener);
    _ = toplevel;
}

fn handleRequestMove(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
    event: *wlr.XdgToplevel.event.Move,
) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_move", listener);
    _ = toplevel;
    _ = event;
}

fn handleRequestResize(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
    event: *wlr.XdgToplevel.event.Resize,
) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_resize", listener);
    _ = toplevel;
    _ = event;
}

fn handleSetTitle(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("set_title", listener);
    _ = toplevel;
}

fn handleSetAppId(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("set_app_id", listener);
    _ = toplevel;
}
