const std = @import("std");

const wlr = @import("wlroots");
const hwc = @import("hwc");

fn out_print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

const PrefixStack = struct {
    parent: ?*PrefixStack,
    more_children: bool,

    fn print(self: *PrefixStack, top: bool) void {
        if (self.parent) |parent| {
            parent.print(false);
        }

        if (self.more_children) {
            out_print("{s}", .{if (top) "  ├─" else "  │ "});
        } else {
            out_print("{s}", .{if (top) "  └─" else "    "});
        }
    }
};

fn dumpNode(node: *wlr.SceneNode, parent: ?*PrefixStack, x: c_int, y: c_int) void {
    if (parent) |p| {
        p.print(true);
    }

    switch (node.type) {
        .tree => out_print(
            "[tree] {},{} ({x})",
            .{ x, y, @intFromPtr(node) },
        ),
        .rect => {
            const wlr_scene_rect = wlr.SceneRect.fromNode(node);
            out_print(
                "[rect] {},{} {}x{} ({x})",
                .{ x, y, wlr_scene_rect.width, wlr_scene_rect.height, @intFromPtr(node) },
            );
        },
        .buffer => {
            const wlr_scene_buffer = wlr.SceneBuffer.fromNode(node);
            out_print(
                "[buffer] {},{} {}x{} ({x})",
                .{ x, y, wlr_scene_buffer.dst_width, wlr_scene_buffer.dst_height, @intFromPtr(node) },
            );
        },
    }

    if (hwc.desktop.SceneDescriptor.fromNode(node)) |scene_descriptor| {
        var buffer: [2048:0]u8 = undefined;
        out_print(" {s}{!s}\n", .{ @tagName(scene_descriptor.focusable), scene_descriptor.focusable.status(&buffer) });
    } else {
        out_print("\n", .{});
    }

    if (node.type != .tree) {
        return;
    }

    const tree: *wlr.SceneTree = @alignCast(@ptrCast(node));

    var stack = PrefixStack{
        .parent = parent,
        .more_children = undefined,
    };

    var it = tree.children.iterator(.forward);
    while (it.next()) |child| {
        if (@intFromPtr(child.link.next.?) == @intFromPtr(&tree.children)) {
            stack.more_children = false;
        } else {
            stack.more_children = true;
        }

        dumpNode(child, &stack, x + child.x, y + child.y);
    }
}

pub fn dump(node: *wlr.SceneNode) void {
    dumpNode(node, null, node.x, node.y);
}
