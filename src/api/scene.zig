const std = @import("std");

const wlr = @import("wlroots");

pub fn dump(node: *wlr.SceneNode) void {
    dumpNode(node, null, node.x, node.y);
}

const PrefixStack = struct {
    parent: ?*PrefixStack,
    more_children: bool,

    fn print(self: *PrefixStack, top: bool) void {
        if (self.parent) |parent| {
            parent.print(false);
        }

        if (self.more_children) {
            std.debug.print("{s}", .{if (top) "  ├─" else "  │ "});
        } else {
            std.debug.print("{s}", .{if (top) "  └─" else "    "});
        }
    }
};

fn dumpNode(node: *wlr.SceneNode, parent: ?*PrefixStack, x: c_int, y: c_int) void {
    if (parent) |p| {
        p.print(true);
    }

    switch (node.type) {
        .tree => std.debug.print(
            "[tree] {},{} ({x})\n",
            .{ x, y, @intFromPtr(node) },
        ),
        .rect => {
            const rect = wlr.SceneRect.fromNode(node);
            std.debug.print(
                "[rect] {},{} {}x{} ({x})\n",
                .{ x, y, rect.width, rect.height, @intFromPtr(node) },
            );
        },
        .buffer => {
            const buffer = wlr.SceneBuffer.fromNode(node);
            std.debug.print(
                "[buffer] {},{} {}x{} ({x})\n",
                .{ x, y, buffer.dst_width, buffer.dst_height, @intFromPtr(node) },
            );
        },
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
