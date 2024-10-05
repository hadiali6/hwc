const std = @import("std");
const log = std.log.scoped(.xdgpopup);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");
const hwc = @import("hwc.zig");

xdg_popup: *wlr.XdgPopup,

commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),

pub fn create(wlr_xdg_popup: *wlr.XdgPopup) error{OutOfMemory}!void {
    // These asserts are fine since tinywl.zig doesn't support anything else that can
    // make xdg popups (e.g. layer shell).
    const parent = wlr.XdgSurface.tryFromWlrSurface(wlr_xdg_popup.parent.?) orelse return;
    const parent_tree = @as(?*wlr.SceneTree, @ptrFromInt(parent.data)) orelse {
        // The xdg surface user data could be left null due to allocation failure.
        return error.OutOfMemory;
    };
    const scene_tree = parent_tree.createSceneXdgSurface(wlr_xdg_popup.base) catch {
        log.err("failed to allocate xdg popup node", .{});
        return error.OutOfMemory;
    };
    wlr_xdg_popup.base.data = @intFromPtr(scene_tree);
    const popup = util.allocator.create(hwc.XdgPopup) catch {
        log.err("failed to allocate new popup", .{});
        return error.OutOfMemory;
    };
    popup.* = .{
        .xdg_popup = wlr_xdg_popup,
    };
    wlr_xdg_popup.base.surface.events.commit.add(&popup.commit);
    wlr_xdg_popup.events.destroy.add(&popup.destroy);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const popup: *hwc.XdgPopup = @fieldParentPtr("commit", listener);
    if (popup.xdg_popup.base.initial_commit) {
        _ = popup.xdg_popup.base.scheduleConfigure();
    }
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const popup: *hwc.XdgPopup = @fieldParentPtr("destroy", listener);
    popup.commit.link.remove();
    popup.destroy.link.remove();
    util.allocator.destroy(popup);
}
