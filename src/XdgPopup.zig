const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");

const log = std.log.scoped(.xdgpopup);

pub const Popup = struct {
    xdg_popup: *wlr.XdgPopup,

    commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(commit),
    destroy: wl.Listener(void) = wl.Listener(void).init(destroy),

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
        const popup = util.gpa.create(Popup) catch {
            log.err("failed to allocate new popup", .{});
            return error.OutOfMemory;
        };
        popup.* = .{
            .xdg_popup = wlr_xdg_popup,
        };
        wlr_xdg_popup.base.surface.events.commit.add(&popup.commit);
        wlr_xdg_popup.events.destroy.add(&popup.destroy);
    }

    fn commit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const popup: *Popup = @fieldParentPtr("commit", listener);
        if (popup.xdg_popup.base.initial_commit) {
            _ = popup.xdg_popup.base.scheduleConfigure();
        }
    }

    fn destroy(listener: *wl.Listener(void)) void {
        const popup: *Popup = @fieldParentPtr("destroy", listener);
        popup.commit.link.remove();
        popup.destroy.link.remove();
        util.gpa.destroy(popup);
    }
};
