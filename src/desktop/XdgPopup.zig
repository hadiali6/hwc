const std = @import("std");
const log = std.log.scoped(.@"desktop.XdgPopup");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

wlr_xdg_popup: *wlr.XdgPopup,
root_tree: *wlr.SceneTree,
parent_tree: *wlr.SceneTree,

destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),
reposition: wl.Listener(void) = wl.Listener(void).init(handleReposition),
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn create(
    allocator: mem.Allocator,
    wlr_xdg_popup: *wlr.XdgPopup,
    root_tree: *wlr.SceneTree,
    parent_tree: *wlr.SceneTree,
) !void {
    const popup = try allocator.create(hwc.desktop.XdgPopup);
    errdefer allocator.destroy(popup);

    popup.* = .{
        .wlr_xdg_popup = wlr_xdg_popup,
        .root_tree = root_tree,
        .parent_tree = try parent_tree.createSceneXdgSurface(wlr_xdg_popup.base),
    };

    wlr_xdg_popup.events.destroy.add(&popup.destroy);
    wlr_xdg_popup.events.reposition.add(&popup.reposition);
    wlr_xdg_popup.base.surface.events.commit.add(&popup.commit);
    wlr_xdg_popup.base.events.new_popup.add(&popup.new_popup);

    log.info("{s}: parent={any}", .{ @src().fn_name, wlr_xdg_popup.parent orelse null });
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("destroy", listener);

    popup.commit.link.remove();
    popup.destroy.link.remove();

    log.info("{s}", .{@src().fn_name});

    server.allocator.destroy(popup);
}

fn handleReposition(listener: *wl.Listener(void)) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("reposition", listener);
    _ = popup;
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("commit", listener);
    if (popup.wlr_xdg_popup.base.initial_commit) {
        _ = popup.wlr_xdg_popup.base.scheduleConfigure();
    }
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("new_popup", listener);

    hwc.desktop.XdgPopup.create(
        server.allocator,
        wlr_xdg_popup,
        popup.root_tree,
        popup.parent_tree,
    ) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });
        if (err == error.OutOfMemory) {
            wlr_xdg_popup.resource.postNoMemory();
        }
    };
}
