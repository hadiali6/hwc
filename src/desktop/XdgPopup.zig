const std = @import("std");
const log = std.log.scoped(.@"desktop.XdgPopup");
const assert = std.debug.assert;
const fmt = std.fmt;
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

// TODO fix unnecessary output damage on toplevels when popups show up

wlr_xdg_popup: *wlr.XdgPopup,
root_tree: *wlr.SceneTree,
surface_tree: *wlr.SceneTree,

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
        .surface_tree = try parent_tree.createSceneXdgSurface(wlr_xdg_popup.base),
    };

    if (popup.wlr_xdg_popup.parent) |parent_wlr_surface| {
        // for now, this is only needed for logging. see parentSurfaceStatus()
        if (hwc.desktop.SceneDescriptor.fromSurface(parent_wlr_surface) == null) {
            assert(parent_wlr_surface.data == 0);
            assert(root_tree != parent_tree);

            parent_wlr_surface.data = @intFromPtr(&popup.root_tree.node);
        }
    }

    wlr_xdg_popup.events.destroy.add(&popup.destroy);
    wlr_xdg_popup.events.reposition.add(&popup.reposition);
    wlr_xdg_popup.base.surface.events.commit.add(&popup.commit);
    wlr_xdg_popup.base.events.new_popup.add(&popup.new_popup);

    log.info("{s}: parent='{!s}'", .{ @src().fn_name, popup.parentSurfaceStatus() });
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("destroy", listener);

    popup.commit.link.remove();
    popup.destroy.link.remove();

    log.info("{s}: parent='{!s}'", .{ @src().fn_name, popup.parentSurfaceStatus() });

    server.mem_allocator.destroy(popup);
}

fn handleReposition(listener: *wl.Listener(void)) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("reposition", listener);
    popup.configure();

    log.debug("{s}: parent='{!s}'", .{ @src().fn_name, popup.parentSurfaceStatus() });
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("commit", listener);

    if (popup.wlr_xdg_popup.base.initial_commit) {
        popup.configure();
    }

    log.debug("{s}: parent='{!s}'", .{ @src().fn_name, popup.parentSurfaceStatus() });
}

fn configure(self: *hwc.desktop.XdgPopup) void {
    // TODO handle set_reactive properly

    const scene_descriptor = hwc.desktop.SceneDescriptor.fromNode(&self.root_tree.node).?;
    const output = switch (scene_descriptor.focusable) {
        .toplevel => |toplevel| toplevel.primary_output,
        .layer_surface => |layer_surface| layer_surface.output,
        else => unreachable,
    };

    var box: wlr.Box = undefined;
    server.output_manager.wlr_output_layout.getBox(output.wlr_output, &box);

    var root_lx: c_int = undefined;
    var root_ly: c_int = undefined;
    _ = self.root_tree.node.coords(&root_lx, &root_ly);

    box.x -= root_lx;
    box.y -= root_ly;

    self.wlr_xdg_popup.unconstrainFromBox(&box);
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const popup: *hwc.desktop.XdgPopup = @fieldParentPtr("new_popup", listener);

    hwc.desktop.XdgPopup.create(
        server.mem_allocator,
        wlr_xdg_popup,
        popup.root_tree,
        popup.surface_tree,
    ) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });
        if (err == error.OutOfMemory) {
            wlr_xdg_popup.resource.postNoMemory();
        }
    };
}

/// For logging purposes
fn parentSurfaceStatus(self: hwc.desktop.XdgPopup) ![:0]const u8 {
    const parent_wlr_surface = self.wlr_xdg_popup.parent orelse return "null";
    const scene_descriptor = hwc.desktop.SceneDescriptor.fromSurface(parent_wlr_surface).?;

    var result_buffer: [2048]u8 = undefined;
    var focusable_status_buffer: [2048]u8 = undefined;

    return fmt.bufPrintZ(&result_buffer, "{s}{!s}", .{
        @tagName(scene_descriptor.focusable),
        scene_descriptor.focusable.status(&focusable_status_buffer),
    });
}
