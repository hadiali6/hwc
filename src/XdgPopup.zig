const std = @import("std");
const log = std.log.scoped(.xdg_popup);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");
const hwc = @import("hwc.zig");

xdg_popup: *wlr.XdgPopup,

root: *wlr.SceneTree,
parent: *wlr.SceneTree,

commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
reposition: wl.Listener(void) = wl.Listener(void).init(handleReposition),
destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn create(
    wlr_xdg_popup: *wlr.XdgPopup,
    root_scene_tree: *wlr.SceneTree,
    parent_scene_tree: *wlr.SceneTree,
) error{OutOfMemory}!void {
    const popup = try util.allocator.create(hwc.XdgPopup);
    errdefer util.allocator.destroy(popup);

    const parent_xdg_scene_tree = try parent_scene_tree.createSceneXdgSurface(wlr_xdg_popup.base);
    errdefer parent_xdg_scene_tree.node.destroy();

    popup.* = .{
        .root = root_scene_tree,
        .parent = parent_xdg_scene_tree,
        .xdg_popup = wlr_xdg_popup,
    };

    wlr_xdg_popup.base.data = @intFromPtr(popup);

    wlr_xdg_popup.base.surface.events.commit.add(&popup.commit);
    wlr_xdg_popup.events.reposition.add(&popup.reposition);
    wlr_xdg_popup.events.destroy.add(&popup.destroy);
    wlr_xdg_popup.base.events.new_popup.add(&popup.new_popup);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const popup: *hwc.XdgPopup = @fieldParentPtr("commit", listener);
    if (popup.xdg_popup.base.initial_commit) {
        _ = popup.xdg_popup.base.scheduleConfigure();
        // handleReposition(&popup.reposition);
    }
}

fn handleReposition(listener: *wl.Listener(void)) void {
    _ = listener;
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const popup: *hwc.XdgPopup = @fieldParentPtr("destroy", listener);

    popup.new_popup.link.remove();
    popup.commit.link.remove();
    popup.reposition.link.remove();
    popup.destroy.link.remove();

    util.allocator.destroy(popup);
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const popup: *hwc.XdgPopup = @fieldParentPtr("new_popup", listener);

    hwc.XdgPopup.create(wlr_xdg_popup, popup.root, popup.parent) catch |err| {
        wlr_xdg_popup.resource.postNoMemory();
        log.err("{s} failed: {}", .{ @src().fn_name, err });
    };
}
