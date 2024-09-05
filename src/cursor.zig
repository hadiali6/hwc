const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

// const Server = @import("server.zig").Server;
const Toplevel = @import("xdgshell.zig").Toplevel;

const server = &@import("main.zig").server;

const log = std.log.scoped(.cursor);

pub const Cursor = struct {
    wlr_cursor: *wlr.Cursor,
    manager: *wlr.XcursorManager,

    motion: wl.Listener(*wlr.Pointer.event.Motion) =
        wl.Listener(*wlr.Pointer.event.Motion).init(cursorMotion),
    motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) =
        wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(cursorMotionAbsolute),
    button: wl.Listener(*wlr.Pointer.event.Button) =
        wl.Listener(*wlr.Pointer.event.Button).init(cursorButton),
    axis: wl.Listener(*wlr.Pointer.event.Axis) =
        wl.Listener(*wlr.Pointer.event.Axis).init(cursorAxis),
    frame: wl.Listener(*wlr.Cursor) =
        wl.Listener(*wlr.Cursor).init(cursorFrame),

    mode: enum { passthrough, move, resize } = .passthrough,
    grabbed_toplevel: ?*Toplevel = null,
    grab_x: f64 = 0,
    grab_y: f64 = 0,
    grab_box: wlr.Box = undefined,
    resize_edges: wlr.Edges = .{},

    pub fn init(self: *Cursor) !void {
        self.* = .{
            .wlr_cursor = try wlr.Cursor.create(),
            .manager = try wlr.XcursorManager.create(null, 24),
        };
        self.wlr_cursor.attachOutputLayout(server.output_layout);
        try self.manager.load(1);
        self.wlr_cursor.events.motion.add(&self.motion);
        self.wlr_cursor.events.motion_absolute.add(&self.motion_absolute);
        self.wlr_cursor.events.button.add(&self.button);
        self.wlr_cursor.events.axis.add(&self.axis);
        self.wlr_cursor.events.frame.add(&self.frame);
    }

    pub fn deinit(self: *Cursor) void {
        self.wlr_cursor.destroy();
    }

    fn cursorMotion(
        listener: *wl.Listener(*wlr.Pointer.event.Motion),
        event: *wlr.Pointer.event.Motion,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("motion", listener);
        cursor.wlr_cursor.move(event.device, event.delta_x, event.delta_y);
        cursor.processCursorMotion(event.time_msec);
    }

    fn cursorMotionAbsolute(
        listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
        event: *wlr.Pointer.event.MotionAbsolute,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("motion_absolute", listener);
        cursor.wlr_cursor.warpAbsolute(event.device, event.x, event.y);
        cursor.processCursorMotion(event.time_msec);
    }

    fn processCursorMotion(self: *Cursor, time_msec: u32) void {
        switch (self.mode) {
            .passthrough => if (server.toplevelAt(self.wlr_cursor.x, self.wlr_cursor.y)) |res| {
                server.seat.pointerNotifyEnter(res.surface, res.sx, res.sy);
                server.seat.pointerNotifyMotion(time_msec, res.sx, res.sy);
            } else {
                self.wlr_cursor.setXcursor(self.manager, "default");
                server.seat.pointerClearFocus();
            },
            .move => {
                const toplevel = self.grabbed_toplevel.?;
                toplevel.geometry.x = @as(i32, @intFromFloat(self.wlr_cursor.x - self.grab_x));
                toplevel.geometry.y = @as(i32, @intFromFloat(self.wlr_cursor.y - self.grab_y));
                toplevel.scene_tree.node.setPosition(toplevel.geometry.x, toplevel.geometry.y);
            },
            .resize => {
                const toplevel = self.grabbed_toplevel.?;
                const border_x = @as(i32, @intFromFloat(self.wlr_cursor.x - self.grab_x));
                const border_y = @as(i32, @intFromFloat(self.wlr_cursor.y - self.grab_y));

                var new_left = self.grab_box.x;
                var new_right = self.grab_box.x + self.grab_box.width;
                var new_top = self.grab_box.y;
                var new_bottom = self.grab_box.y + self.grab_box.height;

                if (self.resize_edges.top) {
                    new_top = border_y;
                    if (new_top >= new_bottom)
                        new_top = new_bottom - 1;
                } else if (self.resize_edges.bottom) {
                    new_bottom = border_y;
                    if (new_bottom <= new_top)
                        new_bottom = new_top + 1;
                }

                if (self.resize_edges.left) {
                    new_left = border_x;
                    if (new_left >= new_right)
                        new_left = new_right - 1;
                } else if (self.resize_edges.right) {
                    new_right = border_x;
                    if (new_right <= new_left)
                        new_right = new_left + 1;
                }

                var geo_box: wlr.Box = undefined;
                toplevel.xdg_toplevel.base.getGeometry(&geo_box);
                toplevel.geometry.x = new_left - geo_box.x;
                toplevel.geometry.y = new_top - geo_box.y;
                toplevel.scene_tree.node.setPosition(
                    toplevel.geometry.x,
                    toplevel.geometry.y,
                );

                const new_width = new_right - new_left;
                const new_height = new_bottom - new_top;
                _ = toplevel.xdg_toplevel.setSize(new_width, new_height);
            },
        }
    }

    fn cursorButton(
        listener: *wl.Listener(*wlr.Pointer.event.Button),
        event: *wlr.Pointer.event.Button,
    ) void {
        const cursor: *Cursor = @fieldParentPtr("button", listener);
        _ = server.seat.pointerNotifyButton(event.time_msec, event.button, event.state);
        if (event.state == .released) {
            cursor.mode = .passthrough;
        } else if (server.toplevelAt(cursor.wlr_cursor.x, cursor.wlr_cursor.y)) |res| {
            server.focusToplevel(res.toplevel, res.surface);
        }
    }

    fn cursorAxis(
        _: *wl.Listener(*wlr.Pointer.event.Axis),
        event: *wlr.Pointer.event.Axis,
    ) void {
        // const cursor: *Cursor = @fieldParentPtr("axis", listener);
        server.seat.pointerNotifyAxis(
            event.time_msec,
            event.orientation,
            event.delta,
            event.delta_discrete,
            event.source,
            event.relative_direction,
        );
    }

    fn cursorFrame(_: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
        // const cursor: *Cursor = @fieldParentPtr("frame", listener);
        server.seat.pointerNotifyFrame();
    }
};
