const std = @import("std");
const log = std.log.scoped(.@"desktop.XdgToplevel");
const assert = std.debug.assert;
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

link: wl.list.Link,
wlr_xdg_toplevel: *wlr.XdgToplevel,
surface_tree: *wlr.SceneTree,
popup_tree: *wlr.SceneTree,
output_tracker: *wlr.SceneBuffer,

x: i32 = 0,
y: i32 = 0,

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

buffer_outputs_update: wl.Listener(*wlr.SceneBuffer.event.OutputsUpdate) =
    wl.Listener(*wlr.SceneBuffer.event.OutputsUpdate).init(handleBufferOutputsUpdate),
buffer_output_enter: wl.Listener(*wlr.SceneOutput) =
    wl.Listener(*wlr.SceneOutput).init(handleBufferOutputEnter),
buffer_output_leave: wl.Listener(*wlr.SceneOutput) =
    wl.Listener(*wlr.SceneOutput).init(handleBufferOutputLeave),

pub fn create(
    allocator: mem.Allocator,
    wlr_xdg_toplevel: *wlr.XdgToplevel,
) !*hwc.desktop.XdgToplevel {
    const toplevel = try allocator.create(hwc.desktop.XdgToplevel);
    errdefer allocator.destroy(toplevel);

    const surface_tree = try server.surface_manager.wlr_scene.tree.createSceneTree();
    errdefer surface_tree.node.destroy();

    // TODO: use current outputs popup layer
    const popup_tree = try server.surface_manager.wlr_scene.tree.createSceneTree();
    errdefer popup_tree.node.destroy();

    toplevel.* = .{
        .link = undefined,
        .wlr_xdg_toplevel = wlr_xdg_toplevel,
        .surface_tree = surface_tree,
        .popup_tree = popup_tree,
        .output_tracker = undefined,
    };

    try hwc.desktop.SceneDescriptor.create(allocator, &surface_tree.node, .{ .toplevel = toplevel });
    try hwc.desktop.SceneDescriptor.create(allocator, &popup_tree.node, .{ .toplevel = toplevel });

    wlr_xdg_toplevel.base.surface.events.unmap.add(&toplevel.unmap);
    errdefer toplevel.unmap.link.remove();

    const xdg_surface_scene_tree = try toplevel.surface_tree.createSceneXdgSurface(wlr_xdg_toplevel.base);

    if (findBuffer(xdg_surface_scene_tree)) |output_tracker| {
        toplevel.output_tracker = output_tracker;
    } else unreachable;

    toplevel.output_tracker.point_accepts_input = struct {
        fn cb(_: *wlr.SceneBuffer, _: *f64, _: *f64) callconv(.C) bool {
            return false;
        }
    }.cb;

    // add listeners that are active over the toplevel's entire lifetime
    wlr_xdg_toplevel.events.destroy.add(&toplevel.destroy);
    wlr_xdg_toplevel.base.surface.events.map.add(&toplevel.map);
    wlr_xdg_toplevel.base.surface.events.commit.add(&toplevel.commit);
    wlr_xdg_toplevel.base.events.new_popup.add(&toplevel.new_popup);

    toplevel.output_tracker.events.outputs_update.add(&toplevel.buffer_outputs_update);
    toplevel.output_tracker.events.output_enter.add(&toplevel.buffer_output_enter);
    toplevel.output_tracker.events.output_leave.add(&toplevel.buffer_output_leave);

    log.info(
        "{s}: app_id='{?s}' title='{?s}'",
        .{ @src().fn_name, toplevel.wlr_xdg_toplevel.app_id, toplevel.wlr_xdg_toplevel.title },
    );

    return toplevel;
}

fn findBuffer(wlr_scene_tree: *wlr.SceneTree) ?*wlr.SceneBuffer {
    var it = wlr_scene_tree.children.iterator(.forward);
    while (it.next()) |wlr_scene_node| {
        switch (wlr_scene_node.type) {
            .tree => return findBuffer(wlr.SceneTree.fromNode(wlr_scene_node)),
            .buffer => {
                log.debug("found buffer", .{});
                return wlr.SceneBuffer.fromNode(wlr_scene_node);
            },
            .rect => {},
        }
    }

    return null;
}

pub fn destroyPopups(self: *hwc.desktop.XdgToplevel) void {
    var it = self.wlr_xdg_toplevel.base.popups.safeIterator(.forward);
    while (it.next()) |wlr_xdg_popup| {
        wlr_xdg_popup.destroy();
    }
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("destroy", listener);

    toplevel.destroyPopups();

    toplevel.link.remove();

    toplevel.surface_tree.node.destroy();
    toplevel.popup_tree.node.destroy();

    toplevel.destroy.link.remove();
    toplevel.map.link.remove();
    toplevel.unmap.link.remove();
    toplevel.commit.link.remove();
    toplevel.new_popup.link.remove();

    log.info(
        "{s}: app_id='{?s}' title='{?s}'",
        .{ @src().fn_name, toplevel.wlr_xdg_toplevel.app_id, toplevel.wlr_xdg_toplevel.title },
    );

    server.allocator.destroy(toplevel);
}

// TODO
fn handleMap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("map", listener);

    server.input_manager.default_seat.focus(.{ .toplevel = toplevel });

    // add listeners that are only active while mapped

    toplevel.wlr_xdg_toplevel.base.events.ack_configure.add(&toplevel.ack_configure);
    toplevel.wlr_xdg_toplevel.events.request_fullscreen.add(&toplevel.request_fullscreen);
    toplevel.wlr_xdg_toplevel.events.request_maximize.add(&toplevel.request_maximize);
    toplevel.wlr_xdg_toplevel.events.request_minimize.add(&toplevel.request_minimize);
    toplevel.wlr_xdg_toplevel.events.request_move.add(&toplevel.request_move);
    toplevel.wlr_xdg_toplevel.events.request_resize.add(&toplevel.request_resize);
    toplevel.wlr_xdg_toplevel.events.set_title.add(&toplevel.set_title);
    toplevel.wlr_xdg_toplevel.events.set_app_id.add(&toplevel.set_app_id);

    log.info(
        "{s}: app_id='{?s}' title='{?s}'",
        .{ @src().fn_name, toplevel.wlr_xdg_toplevel.app_id, toplevel.wlr_xdg_toplevel.title },
    );
}

// TODO
fn handleUnmap(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("unmap", listener);

    // remove listeners that are only active while mapped

    toplevel.ack_configure.link.remove();
    toplevel.request_fullscreen.link.remove();
    toplevel.request_maximize.link.remove();
    toplevel.request_minimize.link.remove();
    toplevel.request_move.link.remove();
    toplevel.request_resize.link.remove();
    toplevel.set_title.link.remove();
    toplevel.set_app_id.link.remove();

    toplevel.buffer_outputs_update.link.remove();
    toplevel.buffer_output_enter.link.remove();
    toplevel.buffer_output_leave.link.remove();
    toplevel.buffer_output_sample.link.remove();

    log.info(
        "{s}: app_id='{?s}' title='{?s}'",
        .{ @src().fn_name, toplevel.wlr_xdg_toplevel.app_id, toplevel.wlr_xdg_toplevel.title },
    );
}

// TODO
fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("commit", listener);

    var box: wlr.Box = undefined;
    toplevel.wlr_xdg_toplevel.base.getGeometry(&box);

    if (toplevel.wlr_xdg_toplevel.base.initial_commit) {
        _ = toplevel.wlr_xdg_toplevel.base.scheduleConfigure();
    }

    log.debug("commit {}x{} {}x{} {?s}", .{
        box.width, box.height, box.x, box.y,
        if (toplevel.output_tracker.primary_output) |primary_wlr_output|
            primary_wlr_output.output.name
        else
            null,
    });
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("new_popup", listener);

    hwc.desktop.XdgPopup.create(
        server.allocator,
        wlr_xdg_popup,
        toplevel.popup_tree,
        toplevel.popup_tree,
    ) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });

        if (err == error.OutOfMemory) {
            wlr_xdg_popup.resource.postNoMemory();
        }
    };
}

// TODO
fn handleAckConfigure(
    listener: *wl.Listener(*wlr.XdgSurface.Configure),
    event: *wlr.XdgSurface.Configure,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("ack_configure", listener);
    _ = toplevel;
    _ = event;
}

// TODO
fn handleRequestFullscreen(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("request_fullscreen", listener);
    _ = toplevel;
}

// TODO
fn handleRequestMaximize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("request_maximize", listener);
    _ = toplevel;
}

// TODO
fn handleRequestMinimize(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("request_minimize", listener);
    _ = toplevel;
}

// TODO (hacky)
fn handleRequestMove(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Move),
    _: *wlr.XdgToplevel.event.Move,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("request_move", listener);
    var cursor = &server.input_manager.default_seat.cursor;

    cursor.mode = .{ .move = toplevel };
    cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(toplevel.x));
    cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(toplevel.y));
}

// TODO (hacky)
fn handleRequestResize(
    listener: *wl.Listener(*wlr.XdgToplevel.event.Resize),
    event: *wlr.XdgToplevel.event.Resize,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("request_resize", listener);
    var cursor = &server.input_manager.default_seat.cursor;

    cursor.mode = .{ .resize = toplevel };
    cursor.resize_edges = event.edges;

    var box: wlr.Box = undefined;
    toplevel.wlr_xdg_toplevel.base.getGeometry(&box);

    const border_x = toplevel.x + box.x + if (event.edges.right) box.width else 0;
    const border_y = toplevel.y + box.y + if (event.edges.bottom) box.height else 0;
    cursor.grab_x = cursor.wlr_cursor.x - @as(f64, @floatFromInt(border_x));
    cursor.grab_y = cursor.wlr_cursor.y - @as(f64, @floatFromInt(border_y));

    cursor.grab_box = box;
    cursor.grab_box.x += toplevel.x;
    cursor.grab_box.y += toplevel.y;
}

// TODO
fn handleSetTitle(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("set_title", listener);
    _ = toplevel;
}

// TODO
fn handleSetAppId(listener: *wl.Listener(void)) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("set_app_id", listener);
    _ = toplevel;
}

fn handleBufferOutputsUpdate(
    listener: *wl.Listener(*wlr.SceneBuffer.event.OutputsUpdate),
    event: *wlr.SceneBuffer.event.OutputsUpdate,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("buffer_outputs_update", listener);

    var buf: [2048:0]u8 = undefined;
    const output_names: ?[]u8 = if (event.size == 0) null else blk: {
        for (0..event.size) |i| {
            _ = std.fmt.bufPrint(&buf, "{s} ", .{event.active[i].output.name}) catch unreachable;
        }
        break :blk &buf;
    };

    log.info("{s}: '{?s}' app_id='{?s}' title='{?s}'", .{
        @src().fn_name,
        output_names,
        toplevel.wlr_xdg_toplevel.app_id,
        toplevel.wlr_xdg_toplevel.title,
    });
}

fn handleBufferOutputEnter(
    listener: *wl.Listener(*wlr.SceneOutput),
    wlr_scene_output: *wlr.SceneOutput,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("buffer_output_enter", listener);

    log.info("{s}: '{s}' app_id='{?s}' title='{?s}'", .{
        @src().fn_name,
        wlr_scene_output.output.name,
        toplevel.wlr_xdg_toplevel.app_id,
        toplevel.wlr_xdg_toplevel.title,
    });
}

fn handleBufferOutputLeave(
    listener: *wl.Listener(*wlr.SceneOutput),
    wlr_scene_output: *wlr.SceneOutput,
) void {
    const toplevel: *hwc.desktop.XdgToplevel = @fieldParentPtr("buffer_output_leave", listener);

    log.info("{s}: '{s}' app_id='{?s}' title='{?s}'", .{
        @src().fn_name,
        wlr_scene_output.output.name,
        toplevel.wlr_xdg_toplevel.app_id,
        toplevel.wlr_xdg_toplevel.title,
    });
}
