const std = @import("std");
const log = std.log.scoped(.@"desktop.LayerSurface");
const assert = std.debug.assert;
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

wlr_layer_surface: *wlr.LayerSurfaceV1,
wlr_scene_layer_surface: *wlr.SceneLayerSurfaceV1,

output: *hwc.desktop.Output,

popup_tree: *wlr.SceneTree,

destroy: wl.Listener(*wlr.LayerSurfaceV1) = wl.Listener(*wlr.LayerSurfaceV1).init(handleDestroy),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),
map: wl.Listener(void) = wl.Listener(void).init(handleMap),
unmap: wl.Listener(void) = wl.Listener(void).init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn create(allocator: mem.Allocator, wlr_layer_surface: *wlr.LayerSurfaceV1) !void {
    const output: *hwc.desktop.Output = @ptrFromInt(wlr_layer_surface.output.?.data);

    const layer_surface = try allocator.create(hwc.desktop.LayerSurface);
    errdefer allocator.destroy(layer_surface);

    const scene_tree = output.layerSurfaceTree(wlr_layer_surface.current.layer);

    layer_surface.* = .{
        .output = output,
        .wlr_layer_surface = wlr_layer_surface,
        .wlr_scene_layer_surface = try scene_tree.createSceneLayerSurfaceV1(wlr_layer_surface),
        .popup_tree = try output.layers.popups.createSceneTree(),
    };

    wlr_layer_surface.events.destroy.add(&layer_surface.destroy);
    wlr_layer_surface.events.new_popup.add(&layer_surface.new_popup);
    wlr_layer_surface.surface.events.map.add(&layer_surface.map);
    wlr_layer_surface.surface.events.unmap.add(&layer_surface.unmap);
    wlr_layer_surface.surface.events.commit.add(&layer_surface.commit);

    log.info("{s}: namespace='{s}'", .{ @src().fn_name, wlr_layer_surface.namespace });
}

fn destroyPopups(self: *hwc.desktop.LayerSurface) void {
    var it = self.wlr_layer_surface.popups.safeIterator(.forward);
    while (it.next()) |wlr_xdg_popup| {
        wlr_xdg_popup.destroy();
    }
}

fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {
    const layer_surface: *hwc.desktop.LayerSurface = @fieldParentPtr("destroy", listener);

    layer_surface.destroyPopups();

    layer_surface.popup_tree.node.destroy();

    layer_surface.destroy.link.remove();
    layer_surface.new_popup.link.remove();
    layer_surface.map.link.remove();
    layer_surface.unmap.link.remove();
    layer_surface.commit.link.remove();

    log.info("{s}: namespace='{s}'", .{ @src().fn_name, layer_surface.wlr_layer_surface.namespace });

    server.allocator.destroy(layer_surface);
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const layer_surface: *hwc.desktop.LayerSurface = @fieldParentPtr("new_popup", listener);

    hwc.desktop.XdgPopup.create(
        server.allocator,
        wlr_xdg_popup,
        layer_surface.popup_tree,
        layer_surface.popup_tree,
    ) catch |err| {
        wlr_xdg_popup.resource.postNoMemory();
        log.err(
            "{s} failed: '{}': namespace='{s}'",
            .{ @src().fn_name, err, layer_surface.wlr_layer_surface.namespace },
        );
    };
}

fn handleMap(listener: *wl.Listener(void)) void {
    const layer_surface: *hwc.desktop.LayerSurface = @fieldParentPtr("map", listener);

    log.info("{s}: namespace='{s}'", .{ @src().fn_name, layer_surface.wlr_layer_surface.namespace });
}

fn handleUnmap(listener: *wl.Listener(void)) void {
    const layer_surface: *hwc.desktop.LayerSurface = @fieldParentPtr("unmap", listener);

    log.info("{s}: namespace='{s}'", .{ @src().fn_name, layer_surface.wlr_layer_surface.namespace });
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const layer_surface: *hwc.desktop.LayerSurface = @fieldParentPtr("commit", listener);
    _ = layer_surface;
}
