const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const Output = @import("Output.zig").Output;

const server = &@import("main.zig").server;

const log = std.log.scoped(.xdgtoplevel);
const gpa = std.heap.c_allocator;

pub const Toplevel = struct {
    link: wl.list.Link = undefined,
    xdg_toplevel: *wlr.XdgToplevel,
    scene_tree: *wlr.SceneTree,

    geometry: wlr.Box = undefined,
    previous_geometry: wlr.Box = undefined,

    commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(commit),
    map: wl.Listener(void) = wl.Listener(void).init(map),
    unmap: wl.Listener(void) = wl.Listener(void).init(unmap),
    destroy: wl.Listener(void) = wl.Listener(void).init(destroy),
    request_move: wl.Listener(*wlr.XdgToplevel.event.Move) =
        wl.Listener(*wlr.XdgToplevel.event.Move).init(requestMove),
    request_resize: wl.Listener(*wlr.XdgToplevel.event.Resize) =
        wl.Listener(*wlr.XdgToplevel.event.Resize).init(requestResize),

    request_minimize: wl.Listener(void) = wl.Listener(void).init(requestMinimize),
    request_maximize: wl.Listener(void) = wl.Listener(void).init(requestMaximize),
    request_fullscreen: wl.Listener(void) = wl.Listener(void).init(requestFullscreen),

    fn commit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
        const toplevel: *Toplevel = @fieldParentPtr("commit", listener);
        // log.debug("Try Commit: {*}", .{toplevel});
        if (toplevel.xdg_toplevel.base.initial_commit) {
            _ = toplevel.xdg_toplevel.setSize(0, 0);
        }
    }

    fn map(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("map", listener);
        log.debug("Try Map: {*}", .{toplevel});
        server.toplevels.prepend(toplevel);
        server.focusToplevel(toplevel, toplevel.xdg_toplevel.base.surface);

        toplevel.xdg_toplevel.base.getGeometry(&toplevel.geometry);
        const usable_area: wlr.Box = getUsableArea(getActiveOutput(toplevel).?);
        if (toplevel.geometry.width > usable_area.width) {
            toplevel.geometry.width = usable_area.width;
        }
        if (toplevel.geometry.height > usable_area.height) {
            toplevel.geometry.height = usable_area.height;
        }
        toplevel.geometry.x = 0;
        toplevel.geometry.y = 0;
    }

    fn unmap(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("unmap", listener);
        log.debug("Try Unmap: {*}", .{toplevel});
        toplevel.link.remove();
    }

    fn destroy(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("destroy", listener);
        log.debug("Try Destroy: {*}", .{toplevel});

        toplevel.commit.link.remove();
        toplevel.map.link.remove();
        toplevel.unmap.link.remove();
        toplevel.destroy.link.remove();
        toplevel.request_move.link.remove();
        toplevel.request_resize.link.remove();
        toplevel.request_minimize.link.remove();
        toplevel.request_maximize.link.remove();
        toplevel.request_fullscreen.link.remove();

        gpa.destroy(toplevel);
    }

    fn requestMove(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
        _: *wlr.XdgToplevel.event.Move,
    ) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_move", listener);
        log.debug("Try Move: {*}", .{toplevel});
        server.cursor.grabbed_toplevel = toplevel;
        server.cursor.mode = .move;
        server.cursor.grab_x = server.cursor.wlr_cursor.x -
            @as(f64, @floatFromInt(toplevel.geometry.x));
        server.cursor.grab_y = server.cursor.wlr_cursor.y -
            @as(f64, @floatFromInt(toplevel.geometry.y));
    }

    fn requestResize(
        listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
        event: *wlr.XdgToplevel.event.Resize,
    ) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_resize", listener);
        log.debug("Try Resize: {*}", .{toplevel});

        server.cursor.grabbed_toplevel = toplevel;
        server.cursor.mode = .resize;
        server.cursor.resize_edges = event.edges;

        var box: wlr.Box = undefined;
        toplevel.xdg_toplevel.base.getGeometry(&box);

        const border_x = toplevel.geometry.x + box.x + if (event.edges.right) box.width else 0;
        const border_y = toplevel.geometry.y + box.y + if (event.edges.bottom) box.height else 0;
        server.cursor.grab_x = server.cursor.wlr_cursor.x - @as(f64, @floatFromInt(border_x));
        server.cursor.grab_y = server.cursor.wlr_cursor.y - @as(f64, @floatFromInt(border_y));

        server.cursor.grab_box = box;
        server.cursor.grab_box.x += toplevel.geometry.x;
        server.cursor.grab_box.y += toplevel.geometry.y;
    }

    fn requestMinimize(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_minimize", listener);
        log.debug("Try Minimize: {*}", .{toplevel});

        const minimize_requested: bool = toplevel.xdg_toplevel.requested.minimized;
        if (minimize_requested) {
            toplevel.previous_geometry = toplevel.geometry;
            toplevel.geometry.y = -toplevel.geometry.height;
            const next_toplevel: *Toplevel = @fieldParentPtr("link", toplevel.link.next.?);
            if (server.toplevels.length() > 1) {
                server.focusToplevel(
                    next_toplevel,
                    next_toplevel.xdg_toplevel.base.surface,
                );
            } else {
                server.focusToplevel(toplevel, toplevel.xdg_toplevel.base.surface);
            }
        } else {
            toplevel.geometry = toplevel.previous_geometry;
        }
        toplevel.scene_tree.node.setPosition(toplevel.geometry.x, toplevel.geometry.y);
    }
    fn requestMaximize(listener: *wl.Listener(void)) void {
        const toplevel: *Toplevel = @fieldParentPtr("request_maximize", listener);
        log.debug("Try Maximize: {*}", .{toplevel});

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
        const toplevel: *Toplevel = @fieldParentPtr("request_fullscreen", listener);
        log.debug("Try Fullscreen: {*}", .{toplevel});

        const is_fullscreen: bool = toplevel.xdg_toplevel.current.fullscreen;
        if (!is_fullscreen) {
            const wlr_output: ?*wlr.Output = getActiveOutput(toplevel);
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
};

fn getUsableArea(output: *wlr.Output) wlr.Box {
    var usable_area: wlr.Box = undefined;
    output.effectiveResolution(&usable_area.width, &usable_area.height);
    return usable_area;
}

fn getActiveOutput(toplevel: *Toplevel) ?*wlr.Output {
    var closest_x: f64 = undefined;
    var closest_y: f64 = undefined;
    const output: ?*wlr.Output = undefined;
    var geo: wlr.Box = undefined;
    toplevel.xdg_toplevel.base.getGeometry(&geo);
    server.output_layout.closestPoint(
        output,
        @floatFromInt(geo.x + @divTrunc(geo.width, 2)),
        @floatFromInt(geo.y + @divTrunc(geo.height, 2)),
        &closest_x,
        &closest_y,
    );
    return server.output_layout.outputAt(closest_x, closest_y);
}
