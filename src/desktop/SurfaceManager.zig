const std = @import("std");
const log = std.log.scoped(.@"desktop.SurfaceManager");
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

wlr_scene: *wlr.Scene,

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
        .wlr_scene = try wlr.Scene.create(),
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
    self.wlr_scene.tree.node.destroy();
    self.new_toplevel.link.remove();
    self.new_layer_surface.link.remove();
    assert(self.toplevels.empty());

    log.info("{s}", .{@src().fn_name});
}

const AtResult = struct {
    wlr_scene_node: *wlr.SceneNode,
    wlr_surface: ?*wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn resultAt(self: *hwc.desktop.SurfaceManager, lx: f64, ly: f64) ?AtResult {
    var sx: f64 = undefined;
    var sy: f64 = undefined;
    const wlr_scene_node = self.wlr_scene.tree.node.at(lx, ly, &sx, &sy) orelse return null;

    const wlr_surface: ?*wlr.Surface = blk: {
        if (wlr_scene_node.type == .buffer) {
            const wlr_scene_buffer = wlr.SceneBuffer.fromNode(wlr_scene_node);

            if (wlr.SceneSurface.tryFromBuffer(wlr_scene_buffer)) |wlr_scene_surface| {
                break :blk wlr_scene_surface.surface;
            }
        }

        break :blk null;
    };

    return .{
        .wlr_scene_node = wlr_scene_node,
        .wlr_surface = wlr_surface,
        .sx = sx,
        .sy = sy,
    };
}

fn handleNewToplevel(
    listener: *wl.Listener(*wlr.XdgToplevel),
    wlr_xdg_toplevel: *wlr.XdgToplevel,
) void {
    const surface_manager: *hwc.desktop.SurfaceManager = @fieldParentPtr("new_toplevel", listener);

    const toplevel = hwc.desktop.XdgToplevel.create(
        server.mem_allocator,
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
    if (wlr_layer_surface.output == null) {
        const seat = server.input_manager.default_seat;

        if (server.output_manager.outputs.empty() or seat.focused_output == null) {
            log.err("{s} failed: no output to render layer surface", .{@src().fn_name});
            return;
        }

        const output = seat.focused_output orelse unreachable;
        wlr_layer_surface.output = output.wlr_output;
    }

    hwc.desktop.LayerSurface.create(server.mem_allocator, wlr_layer_surface) catch |err| {
        log.err("{s} failed: '{}'", .{ @src().fn_name, err });

        if (err == error.OutOfMemory) {
            wlr_layer_surface.resource.postNoMemory();
        }
    };
}
