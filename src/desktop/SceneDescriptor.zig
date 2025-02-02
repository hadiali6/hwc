const std = @import("std");
const log = std.log.scoped(.@"desktop.SceneDescriptor");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

wlr_scene_node: *wlr.SceneNode,
focusable: hwc.desktop.Focusable,

destroy: wl.Listener(void) = wl.Listener(void).init(handleDestroy),

pub fn create(
    allocator: mem.Allocator,
    wlr_scene_node: *wlr.SceneNode,
    focusable: hwc.desktop.Focusable,
) !void {
    const scene_descriptor = try allocator.create(hwc.desktop.SceneDescriptor);
    errdefer allocator.destroy(scene_descriptor);

    scene_descriptor.* = .{
        .wlr_scene_node = wlr_scene_node,
        .focusable = focusable,
    };

    wlr_scene_node.data = @intFromPtr(scene_descriptor);

    wlr_scene_node.events.destroy.add(&scene_descriptor.destroy);

    {
        var buffer: [1024]u8 = undefined;

        log.info("{s}: {s}:{!s}", .{
            @src().fn_name,
            @tagName(focusable),
            focusable.status(&buffer),
        });
    }
}

pub fn fromNode(wlr_scene_node: *wlr.SceneNode) ?*hwc.desktop.SceneDescriptor {
    var current_node = wlr_scene_node;

    while (true) {
        if (@as(?*hwc.desktop.SceneDescriptor, @ptrFromInt(current_node.data))) |scene_descriptor| {
            return scene_descriptor;
        }

        if (current_node.parent) |parent_tree| {
            current_node = &parent_tree.node;
        } else {
            return null;
        }
    }
}

pub fn fromSurface(wlr_surface: *wlr.Surface) ?*hwc.desktop.SceneDescriptor {
    if (@as(?*wlr.SceneNode, @ptrFromInt(wlr_surface.getRootSurface().data))) |wlr_scene_node| {
        return fromNode(wlr_scene_node);
    } else {
        return null;
    }
}

fn handleDestroy(listener: *wl.Listener(void)) void {
    const scene_descriptor: *hwc.desktop.SceneDescriptor = @fieldParentPtr("destroy", listener);

    scene_descriptor.destroy.link.remove();
    scene_descriptor.wlr_scene_node.data = 0;

    {
        var buffer: [1024]u8 = undefined;

        log.info("{s}: {s}:{!s}", .{
            @src().fn_name,
            @tagName(scene_descriptor.focusable),
            scene_descriptor.focusable.status(&buffer),
        });
    }

    server.allocator.destroy(scene_descriptor);
}
