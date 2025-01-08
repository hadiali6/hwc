const std = @import("std");
const log = std.log.scoped(.xdgtoplevel);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");
const hwc = @import("hwc.zig");

const server = &@import("root").server;

link: wl.list.Link = undefined,
xdg_toplevel: *wlr.XdgToplevel,
scene_tree: *wlr.SceneTree,
geometry: wlr.Box = undefined,
previous_geometry: wlr.Box = undefined,
decoration: ?hwc.XdgDecoration = null,
keyboard_shortcuts_inhibit: bool = false,

commit: wl.Listener(*wlr.Surface) =
    wl.Listener(*wlr.Surface).init(handleCommit),
map: wl.Listener(void) = wl.Listener(void).init(handleMap),
unmap: wl.Listener(void) = wl.Listener(void).init(handleUnmap),
destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),
new_popup: wl.Listener(*wlr.XdgPopup) =
    wl.Listener(*wlr.XdgPopup).init(handleNewPopup),
request_fullscreen: wl.Listener(void) =
    wl.Listener(void).init(requestFullscreen),
request_maximize: wl.Listener(void) =
    wl.Listener(void).init(requestMaximize),
request_minimize: wl.Listener(void) =
    wl.Listener(void).init(requestMinimize),
request_move: wl.Listener(*wlr.XdgToplevel.event.Move) =
    wl.Listener(*wlr.XdgToplevel.event.Move).init(handleMove),
request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) =
    wl.Listener(*wlr.XdgToplevel.event.Resize).init(handleResize),

pub fn create(wlr_toplevel: *wlr.XdgToplevel) error{OutOfMemory}!void {
    const toplevel = util.allocator.create(hwc.XdgToplevel) catch {
        log.err("failed to allocate new toplevel", .{});
        return error.OutOfMemory;
    };

    toplevel.* = .{
        .xdg_toplevel = wlr_toplevel,
        .scene_tree = server.scene.tree.createSceneXdgSurface(wlr_toplevel.base) catch {
            util.allocator.destroy(toplevel);
            log.err("failed to allocate new toplevel", .{});
            return error.OutOfMemory;
        },
    };

    toplevel.scene_tree.node.data = @intFromPtr(toplevel);
    wlr_toplevel.base.data = @intFromPtr(toplevel);
    wlr_toplevel.base.surface.data = @intFromPtr(&toplevel.scene_tree.node);

    wlr_toplevel.base.surface.events.commit.add(&toplevel.commit);
    wlr_toplevel.base.surface.events.map.add(&toplevel.map);
    wlr_toplevel.base.surface.events.unmap.add(&toplevel.unmap);
    wlr_toplevel.base.events.new_popup.add(&toplevel.new_popup);
    wlr_toplevel.events.destroy.add(&toplevel.destroy);
}

pub fn destroyPopups(self: *hwc.XdgToplevel) void {
    var iterator = self.xdg_toplevel.base.popups.safeIterator(.forward);
    while (iterator.next()) |wlr_xdg_popup| {
        wlr_xdg_popup.destroy();
    }
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("commit", listener);
    if (toplevel.xdg_toplevel.base.initial_commit) {
        _ = toplevel.xdg_toplevel.setSize(0, 0);
    }
}

fn handleMap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("map", listener);
    {
        var events = toplevel.xdg_toplevel.events;
        events.request_move.add(&toplevel.request_move);
        events.request_resize.add(&toplevel.request_resize);
        events.request_minimize.add(&toplevel.request_minimize);
        events.request_maximize.add(&toplevel.request_maximize);
        events.request_fullscreen.add(&toplevel.request_fullscreen);
    }

    server.mapped_toplevels.prepend(toplevel);

    {
        // TODO: choose a proper seat so other seats arent bothered
        var iterator = server.input_manager.seats.iterator(.forward);
        while (iterator.next()) |seat| {
            seat.focus(.{ .toplevel = toplevel });
        }
    }

    toplevel.xdg_toplevel.base.getGeometry(&toplevel.geometry);
    const usable_area: wlr.Box = getUsableArea(toplevel.getActiveOutput().?);
    if (toplevel.geometry.width > usable_area.width) {
        toplevel.geometry.width = usable_area.width;
    }
    if (toplevel.geometry.height > usable_area.height) {
        toplevel.geometry.height = usable_area.height;
    }
    toplevel.geometry.x = 0;
    toplevel.geometry.y = 0;
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("unmap", listener);
    toplevel.link.remove();
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("destroy", listener);

    toplevel.commit.link.remove();
    toplevel.map.link.remove();
    toplevel.unmap.link.remove();
    toplevel.destroy.link.remove();
    toplevel.request_move.link.remove();
    toplevel.request_resize.link.remove();
    toplevel.request_minimize.link.remove();
    toplevel.request_maximize.link.remove();
    toplevel.request_fullscreen.link.remove();
    toplevel.new_popup.link.remove();

    // The wlr_surface may outlive the wlr_xdg_toplevel so we must clean up the user data.
    toplevel.xdg_toplevel.base.surface.data = 0;

    util.allocator.destroy(toplevel);
}

fn handleMove(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
    _: *wlr.XdgToplevel.event.Move,
) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_move", listener);
    var cursor = &server.input_manager.defaultSeat().cursor;

    cursor.grabbed_toplevel = toplevel;
    cursor.mode = .move;
    cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(toplevel.geometry.x));
    cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(toplevel.geometry.y));
}

fn handleResize(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
    event: *wlr.XdgToplevel.event.Resize,
) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_resize", listener);
    var cursor = &server.input_manager.defaultSeat().cursor;

    cursor.grabbed_toplevel = toplevel;
    cursor.mode = .resize;
    cursor.resize_edges = event.edges;

    var box: wlr.Box = undefined;
    toplevel.xdg_toplevel.base.getGeometry(&box);

    const border_x = toplevel.geometry.x + box.x + if (event.edges.right) box.width else 0;
    const border_y = toplevel.geometry.y + box.y + if (event.edges.bottom) box.height else 0;
    cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(border_x));
    cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(border_y));

    cursor.grab_box = box;
    cursor.grab_box.x += toplevel.geometry.x;
    cursor.grab_box.y += toplevel.geometry.y;
}

fn requestMinimize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_minimize", listener);

    const minimize_requested: bool = toplevel.xdg_toplevel.requested.minimized;
    if (minimize_requested) {
        toplevel.previous_geometry = toplevel.geometry;
        toplevel.geometry.y = -toplevel.geometry.height;
        const next_toplevel: *hwc.XdgToplevel = @fieldParentPtr("link", toplevel.link.next.?);
        if (server.mapped_toplevels.length() > 1) {
            // TODO: choose a proper seat so other seats arent bothered
            var iterator = server.input_manager.seats.iterator(.forward);
            while (iterator.next()) |seat| {
                seat.focus(.{ .toplevel = next_toplevel });
            }
        } else {
            // TODO: choose a proper seat so other seats arent bothered
            var iterator = server.input_manager.seats.iterator(.forward);
            while (iterator.next()) |seat| {
                seat.focus(.{ .toplevel = toplevel });
            }
        }
    } else {
        toplevel.geometry = toplevel.previous_geometry;
    }
    toplevel.scene_tree.node.setPosition(toplevel.geometry.x, toplevel.geometry.y);
}

fn requestMaximize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_maximize", listener);

    var usable_area: wlr.Box = getUsableArea(getActiveOutput(toplevel).?);
    const is_maximized: bool = toplevel.xdg_toplevel.current.maximized;
    if (!is_maximized) {
        toplevel.previous_geometry = toplevel.geometry;
        toplevel.geometry.x = 0;
        toplevel.geometry.y = 0;
    } else {
        usable_area = toplevel.previous_geometry;
        toplevel.geometry.x = toplevel.previous_geometry.x;
        toplevel.geometry.y = toplevel.previous_geometry.y;
    }
    _ = toplevel.xdg_toplevel.setSize(usable_area.width, usable_area.height);
    _ = toplevel.xdg_toplevel.setMaximized(!is_maximized);
    toplevel.scene_tree.node.setPosition(toplevel.geometry.x, toplevel.geometry.y);
}

fn requestFullscreen(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.XdgToplevel = @fieldParentPtr("request_fullscreen", listener);

    const is_fullscreen: bool = toplevel.xdg_toplevel.current.fullscreen;
    if (!is_fullscreen) {
        const wlr_output: ?*wlr.Output = toplevel.getActiveOutput();
        var output_box: wlr.Box = undefined;
        server.output_layout.getBox(wlr_output, &output_box);
        toplevel.previous_geometry = toplevel.geometry;
        toplevel.geometry.x = 0;
        toplevel.geometry.y = 0;
        toplevel.geometry.height = output_box.height;
        toplevel.geometry.width = output_box.width;
        toplevel.scene_tree.node.raiseToTop();
    } else {
        toplevel.geometry = toplevel.previous_geometry;
    }
    _ = toplevel.xdg_toplevel.setSize(
        toplevel.geometry.width,
        toplevel.geometry.height,
    );
    _ = toplevel.xdg_toplevel.setFullscreen(!is_fullscreen);
    toplevel.scene_tree.node.setPosition(toplevel.geometry.x, toplevel.geometry.y);
}

fn handleNewPopup(
    _: *wl.Listener(*wlr.XdgPopup),
    wlr_xdg_popup: *wlr.XdgPopup,
) void {
    hwc.XdgPopup.create(wlr_xdg_popup) catch {
        wlr_xdg_popup.resource.postNoMemory();
        return;
    };
}

fn getUsableArea(output: *wlr.Output) wlr.Box {
    var usable_area: wlr.Box = undefined;
    output.effectiveResolution(&usable_area.width, &usable_area.height);
    return usable_area;
}

pub fn getActiveOutput(self: *hwc.XdgToplevel) ?*wlr.Output {
    const output: ?*wlr.Output = undefined;

    var closest_x: f64 = undefined;
    var closest_y: f64 = undefined;

    var geo: wlr.Box = undefined;
    self.xdg_toplevel.base.getGeometry(&geo);

    server.output_layout.closestPoint(
        output,
        @floatFromInt(geo.x + @divTrunc(geo.width, 2)),
        @floatFromInt(geo.y + @divTrunc(geo.height, 2)),
        &closest_x,
        &closest_y,
    );

    return server.output_layout.outputAt(closest_x, closest_y);
}
