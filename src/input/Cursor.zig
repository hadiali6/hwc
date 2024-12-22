const std = @import("std");
const log = std.log.scoped(.cursor);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

const Mode = enum { passthrough, move, resize };

const LayoutPoint = struct {
    lx: f64,
    ly: f64,
};

wlr_cursor: *wlr.Cursor,
xcursor_manager: *wlr.XcursorManager,

/// The pointer constraint for the surface that currently has keyboard focus, if any.
/// This constraint is not necessarily active, activation only occurs once the cursor
/// has been moved inside the constraint region.
constraint: ?*hwc.input.PointerConstraint = null,

/// Keeps track of the last known location of all touch points in layout coordinates.
/// This information is necessary for proper touch dnd support if there are multiple touch points.
touch_points: std.AutoHashMapUnmanaged(i32, LayoutPoint) = .{},

mode: Mode = .passthrough,
grabbed_toplevel: ?*hwc.XdgToplevel = null,
grab_x: f64 = 0,
grab_y: f64 = 0,
grab_box: wlr.Box = undefined,
resize_edges: wlr.Edges = .{},

axis: wl.Listener(*wlr.Pointer.event.Axis) =
    wl.Listener(*wlr.Pointer.event.Axis).init(handleAxis),
button: wl.Listener(*wlr.Pointer.event.Button) =
    wl.Listener(*wlr.Pointer.event.Button).init(handleButton),
frame: wl.Listener(*wlr.Cursor) =
    wl.Listener(*wlr.Cursor).init(handleFrame),
motion: wl.Listener(*wlr.Pointer.event.Motion) =
    wl.Listener(*wlr.Pointer.event.Motion).init(handleMotion),
motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) =
    wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(handleMotionAbsolute),

pinch_begin: wl.Listener(*wlr.Pointer.event.PinchBegin) =
    wl.Listener(*wlr.Pointer.event.PinchBegin).init(handlePinchBegin),
pinch_update: wl.Listener(*wlr.Pointer.event.PinchUpdate) =
    wl.Listener(*wlr.Pointer.event.PinchUpdate).init(handlePinchUpdate),
pinch_end: wl.Listener(*wlr.Pointer.event.PinchEnd) =
    wl.Listener(*wlr.Pointer.event.PinchEnd).init(handlePinchEnd),

swipe_begin: wl.Listener(*wlr.Pointer.event.SwipeBegin) =
    wl.Listener(*wlr.Pointer.event.SwipeBegin).init(handleSwipeBegin),
swipe_update: wl.Listener(*wlr.Pointer.event.SwipeUpdate) =
    wl.Listener(*wlr.Pointer.event.SwipeUpdate).init(handleSwipeUpdate),
swipe_end: wl.Listener(*wlr.Pointer.event.SwipeEnd) =
    wl.Listener(*wlr.Pointer.event.SwipeEnd).init(handleSwipeEnd),

hold_begin: wl.Listener(*wlr.Pointer.event.HoldBegin) =
    wl.Listener(*wlr.Pointer.event.HoldBegin).init(handleHoldBegin),
hold_end: wl.Listener(*wlr.Pointer.event.HoldEnd) =
    wl.Listener(*wlr.Pointer.event.HoldEnd).init(handleHoldEnd),

touch_up: wl.Listener(*wlr.Touch.event.Up) =
    wl.Listener(*wlr.Touch.event.Up).init(handleTouchUp),
touch_down: wl.Listener(*wlr.Touch.event.Down) =
    wl.Listener(*wlr.Touch.event.Down).init(handleTouchDown),
touch_motion: wl.Listener(*wlr.Touch.event.Motion) =
    wl.Listener(*wlr.Touch.event.Motion).init(handleTouchMotion),
touch_cancel: wl.Listener(*wlr.Touch.event.Cancel) =
    wl.Listener(*wlr.Touch.event.Cancel).init(handleTouchCancel),
touch_frame: wl.Listener(void) =
    wl.Listener(void).init(handleTouchFrame),

tablet_tool_axis: wl.Listener(*wlr.Tablet.event.Axis) =
    wl.Listener(*wlr.Tablet.event.Axis).init(handleTabletToolAxis),
tablet_tool_proximity: wl.Listener(*wlr.Tablet.event.Proximity) =
    wl.Listener(*wlr.Tablet.event.Proximity).init(handleTabletToolProximity),
tablet_tool_tip: wl.Listener(*wlr.Tablet.event.Tip) =
    wl.Listener(*wlr.Tablet.event.Tip).init(handleTabletToolTip),
tablet_tool_button: wl.Listener(*wlr.Tablet.event.Button) =
    wl.Listener(*wlr.Tablet.event.Button).init(handleTabletToolButton),

pub fn init(self: *hwc.input.Cursor) !void {
    self.* = .{
        .wlr_cursor = try wlr.Cursor.create(),
        .xcursor_manager = try wlr.XcursorManager.create(null, 24),
    };

    self.wlr_cursor.attachOutputLayout(server.output_layout);
    try self.xcursor_manager.load(1);

    self.wlr_cursor.events.axis.add(&self.axis);
    self.wlr_cursor.events.button.add(&self.button);
    self.wlr_cursor.events.frame.add(&self.frame);
    self.wlr_cursor.events.motion.add(&self.motion);
    self.wlr_cursor.events.motion_absolute.add(&self.motion_absolute);

    self.wlr_cursor.events.pinch_begin.add(&self.pinch_begin);
    self.wlr_cursor.events.pinch_update.add(&self.pinch_update);
    self.wlr_cursor.events.pinch_end.add(&self.pinch_end);

    self.wlr_cursor.events.swipe_begin.add(&self.swipe_begin);
    self.wlr_cursor.events.swipe_update.add(&self.swipe_update);
    self.wlr_cursor.events.swipe_end.add(&self.swipe_end);

    self.wlr_cursor.events.hold_begin.add(&self.hold_begin);
    self.wlr_cursor.events.hold_end.add(&self.hold_end);

    self.wlr_cursor.events.touch_up.add(&self.touch_up);
    self.wlr_cursor.events.touch_down.add(&self.touch_down);
    self.wlr_cursor.events.touch_motion.add(&self.touch_motion);
    self.wlr_cursor.events.touch_cancel.add(&self.touch_cancel);
    self.wlr_cursor.events.touch_frame.add(&self.touch_frame);

    self.wlr_cursor.events.tablet_tool_axis.add(&self.tablet_tool_axis);
    self.wlr_cursor.events.tablet_tool_proximity.add(&self.tablet_tool_proximity);
    self.wlr_cursor.events.tablet_tool_tip.add(&self.tablet_tool_tip);
    self.wlr_cursor.events.tablet_tool_button.add(&self.tablet_tool_button);
}

pub fn deinit(self: *hwc.input.Cursor) void {
    self.axis.link.remove();
    self.button.link.remove();
    self.frame.link.remove();
    self.motion.link.remove();
    self.motion_absolute.link.remove();

    self.pinch_begin.link.remove();
    self.pinch_update.link.remove();
    self.pinch_end.link.remove();

    self.swipe_begin.link.remove();
    self.swipe_update.link.remove();
    self.swipe_end.link.remove();

    self.hold_begin.link.remove();
    self.hold_end.link.remove();

    self.wlr_cursor.destroy();
}

fn handleAxis(
    _: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    server.input_manager.seat.wlr_seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );
}

fn handleButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("button", listener);

    _ = server.input_manager.seat.wlr_seat.pointerNotifyButton(
        event.time_msec,
        event.button,
        event.state,
    );

    if (event.state == .released) {
        cursor.mode = .passthrough;
    } else if (server.toplevelAt(
        cursor.wlr_cursor.x,
        cursor.wlr_cursor.y,
    )) |result| {
        server.focusToplevel(result.toplevel, result.surface);
    }
}

fn handleFrame(_: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    server.input_manager.seat.wlr_seat.pointerNotifyFrame();
}

fn handleMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion", listener);

    var dx: f64 = event.delta_x;
    var dy: f64 = event.delta_y;

    if (cursor.constraint) |constraint| {
        if (constraint.state == .active) {
            switch (constraint.wlr_pointer_constraint.type) {
                .locked => {
                    sendRelativeMotion(
                        event.time_msec,
                        event.delta_x,
                        event.delta_y,
                        event.unaccel_dx,
                        event.unaccel_dy,
                    );
                    return;
                },
                .confined => constraint.confine(&dx, &dy),
            }
        }
    }

    cursor.wlr_cursor.move(event.device, dx, dy);

    cursor.processMotion(
        event.time_msec,
        event.delta_x,
        event.delta_y,
        event.unaccel_dx,
        event.unaccel_dy,
    );
}

fn handleMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion_absolute", listener);
    cursor.wlr_cursor.warpAbsolute(event.device, event.x, event.y);

    var lx: f64 = undefined;
    var ly: f64 = undefined;
    cursor.wlr_cursor.absoluteToLayoutCoords(
        event.device,
        event.x,
        event.y,
        &lx,
        &ly,
    );

    const dx = lx - cursor.wlr_cursor.x;
    const dy = ly - cursor.wlr_cursor.y;

    cursor.processMotion(event.time_msec, dx, dy, dx, dy);
}

fn sendRelativeMotion(
    time_msec: u32,
    dx: f64,
    dy: f64,
    unaccel_dx: f64,
    unaccel_dy: f64,
) void {
    server.input_manager.relative_pointer_manager.sendRelativeMotion(
        server.input_manager.seat.wlr_seat,
        @as(u64, time_msec) * 1000,
        dx,
        dy,
        unaccel_dx,
        unaccel_dy,
    );
}

fn processMotion(
    self: *hwc.input.Cursor,
    time_msec: u32,
    delta_x: f64,
    delta_y: f64,
    unaccel_dx: f64,
    unaccel_dy: f64,
) void {
    sendRelativeMotion(time_msec, delta_x, delta_y, unaccel_dx, unaccel_dy);

    switch (self.mode) {
        .passthrough => {
            self.passthrough(time_msec);
            if (self.constraint) |constraint| {
                constraint.maybeActivate();
            }
        },
        .move => self.move(),
        .resize => self.resize(),
    }
}

fn passthrough(self: *hwc.input.Cursor, time_msec: u32) void {
    const wlr_seat = server.input_manager.seat.wlr_seat;

    if (server.toplevelAt(self.wlr_cursor.x, self.wlr_cursor.y)) |result| {
        wlr_seat.pointerNotifyEnter(result.surface, result.sx, result.sy);
        wlr_seat.pointerNotifyMotion(time_msec, result.sx, result.sy);
    } else {
        self.wlr_cursor.setXcursor(self.xcursor_manager, "default");
        wlr_seat.pointerClearFocus();
    }
}

fn move(self: *hwc.input.Cursor) void {
    const toplevel: *hwc.XdgToplevel = self.grabbed_toplevel orelse blk: {
        const toplevel_result_at_cursor = server.toplevelAt(
            self.wlr_cursor.x,
            self.wlr_cursor.y,
        ) orelse return;
        break :blk toplevel_result_at_cursor.toplevel;
    };

    toplevel.geometry.x = @as(
        i32,
        @intFromFloat(self.wlr_cursor.x - self.grab_x),
    );
    toplevel.geometry.y = @as(
        i32,
        @intFromFloat(self.wlr_cursor.y - self.grab_y),
    );

    toplevel.scene_tree.node.setPosition(
        toplevel.geometry.x,
        toplevel.geometry.y,
    );
}

fn resize(self: *hwc.input.Cursor) void {
    const toplevel: *hwc.XdgToplevel = self.grabbed_toplevel orelse blk: {
        const toplevel_result_at_cursor = server.toplevelAt(
            self.wlr_cursor.x,
            self.wlr_cursor.y,
        ) orelse return;
        break :blk toplevel_result_at_cursor.toplevel;
    };

    const border_x = @as(
        i32,
        @intFromFloat(self.wlr_cursor.x - self.grab_x),
    );
    const border_y = @as(
        i32,
        @intFromFloat(self.wlr_cursor.y - self.grab_y),
    );

    var new_left = self.grab_box.x;
    var new_right = self.grab_box.x + self.grab_box.width;
    var new_top = self.grab_box.y;
    var new_bottom = self.grab_box.y + self.grab_box.height;

    if (self.resize_edges.top) {
        new_top = border_y;
        if (new_top >= new_bottom) new_top = new_bottom - 1;
    } else if (self.resize_edges.bottom) {
        new_bottom = border_y;
        if (new_bottom <= new_top) new_bottom = new_top + 1;
    }

    if (self.resize_edges.left) {
        new_left = border_x;
        if (new_left >= new_right) new_left = new_right - 1;
    } else if (self.resize_edges.right) {
        new_right = border_x;
        if (new_right <= new_left) new_right = new_left + 1;
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
}

fn handlePinchBegin(
    _: *wl.Listener(*wlr.Pointer.event.PinchBegin),
    event: *wlr.Pointer.event.PinchBegin,
) void {
    server.input_manager.pointer_gestures.sendPinchBegin(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.fingers,
    );
}

fn handlePinchUpdate(
    _: *wl.Listener(*wlr.Pointer.event.PinchUpdate),
    event: *wlr.Pointer.event.PinchUpdate,
) void {
    server.input_manager.pointer_gestures.sendPinchUpdate(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.dx,
        event.dy,
        event.scale,
        event.rotation,
    );
}

fn handlePinchEnd(
    _: *wl.Listener(*wlr.Pointer.event.PinchEnd),
    event: *wlr.Pointer.event.PinchEnd,
) void {
    server.input_manager.pointer_gestures.sendPinchEnd(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleSwipeBegin(
    _: *wl.Listener(*wlr.Pointer.event.SwipeBegin),
    event: *wlr.Pointer.event.SwipeBegin,
) void {
    server.input_manager.pointer_gestures.sendSwipeBegin(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.fingers,
    );
}

fn handleSwipeUpdate(
    _: *wl.Listener(*wlr.Pointer.event.SwipeUpdate),
    event: *wlr.Pointer.event.SwipeUpdate,
) void {
    server.input_manager.pointer_gestures.sendSwipeUpdate(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.dx,
        event.dy,
    );
}

fn handleSwipeEnd(
    _: *wl.Listener(*wlr.Pointer.event.SwipeEnd),
    event: *wlr.Pointer.event.SwipeEnd,
) void {
    server.input_manager.pointer_gestures.sendPinchEnd(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleHoldBegin(
    _: *wl.Listener(*wlr.Pointer.event.HoldBegin),
    event: *wlr.Pointer.event.HoldBegin,
) void {
    server.input_manager.pointer_gestures.sendHoldBegin(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.fingers,
    );
}

fn handleHoldEnd(
    _: *wl.Listener(*wlr.Pointer.event.HoldEnd),
    event: *wlr.Pointer.event.HoldEnd,
) void {
    server.input_manager.pointer_gestures.sendHoldEnd(
        server.input_manager.seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleTouchUp(listener: *wl.Listener(*wlr.Touch.event.Up), event: *wlr.Touch.event.Up) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_up", listener);

    if (cursor.touch_points.remove(event.touch_id)) {
        _ = server.input_manager.seat.wlr_seat.touchNotifyUp(event.time_msec, event.touch_id);
    }
}

fn handleTouchDown(listener: *wl.Listener(*wlr.Touch.event.Down), event: *wlr.Touch.event.Down) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_down", listener);

    var lx: f64 = undefined;
    var ly: f64 = undefined;
    cursor.wlr_cursor.absoluteToLayoutCoords(event.device, event.x, event.y, &lx, &ly);

    cursor.touch_points.putNoClobber(util.allocator, event.touch_id, .{ .lx = lx, .ly = ly }) catch {
        log.err("out of memory", .{});
        return;
    };

    if (server.toplevelAt(lx, ly)) |result| {
        server.focusToplevel(result.toplevel, result.surface);

        _ = server.input_manager.seat.wlr_seat.touchNotifyDown(
            result.surface,
            event.time_msec,
            event.touch_id,
            event.x,
            event.y,
        );
    }
}

fn handleTouchMotion(listener: *wl.Listener(*wlr.Touch.event.Motion), event: *wlr.Touch.event.Motion) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_motion", listener);

    if (cursor.touch_points.getPtr(event.touch_id)) |point| {
        cursor.wlr_cursor.absoluteToLayoutCoords(
            event.device,
            event.x,
            event.y,
            &point.lx,
            &point.ly,
        );

        if (server.toplevelAt(point.lx, point.ly)) |result| {
            server.input_manager.seat.wlr_seat.touchNotifyMotion(
                event.time_msec,
                event.touch_id,
                result.sx,
                result.sy,
            );
        }
    }
}

fn handleTouchCancel(
    listener: *wl.Listener(*wlr.Touch.event.Cancel),
    _: *wlr.Touch.event.Cancel,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_cancel", listener);
    const wlr_seat = server.input_manager.seat.wlr_seat;

    cursor.touch_points.clearRetainingCapacity();

    while (wlr_seat.touch_state.touch_points.first()) |touch_point| {
        wlr_seat.touchNotifyCancel(touch_point.client);
    }
}

fn handleTouchFrame(_: *wl.Listener(void)) void {
    server.input_manager.seat.wlr_seat.touchNotifyFrame();
}

fn handleTabletToolAxis(
    _: *wl.Listener(*wlr.Tablet.event.Axis),
    event: *wlr.Tablet.event.Axis,
) void {
    const device: *hwc.input.Device = @ptrFromInt(event.device.data);
    const tablet: *hwc.input.Tablet = @fieldParentPtr("device", device);
    const tool = hwc.input.Tablet.Tool.get(
        server.input_manager.seat.wlr_seat,
        tablet,
        event.tool,
    ) catch return;

    tool.axis(tablet, event);
}

fn handleTabletToolProximity(
    _: *wl.Listener(*wlr.Tablet.event.Proximity),
    event: *wlr.Tablet.event.Proximity,
) void {
    const device: *hwc.input.Device = @ptrFromInt(event.device.data);
    const tablet: *hwc.input.Tablet = @fieldParentPtr("device", device);
    const tool = hwc.input.Tablet.Tool.get(
        server.input_manager.seat.wlr_seat,
        tablet,
        event.tool,
    ) catch return;

    tool.proximity(tablet, event);
}
fn handleTabletToolTip(
    _: *wl.Listener(*wlr.Tablet.event.Tip),
    event: *wlr.Tablet.event.Tip,
) void {
    const device: *hwc.input.Device = @ptrFromInt(event.device.data);
    const tablet: *hwc.input.Tablet = @fieldParentPtr("device", device);
    const tool = hwc.input.Tablet.Tool.get(
        server.input_manager.seat.wlr_seat,
        tablet,
        event.tool,
    ) catch return;

    tool.tip(tablet, event);
}
fn handleTabletToolButton(
    _: *wl.Listener(*wlr.Tablet.event.Button),
    event: *wlr.Tablet.event.Button,
) void {
    const device: *hwc.input.Device = @ptrFromInt(event.device.data);
    const tablet: *hwc.input.Tablet = @fieldParentPtr("device", device);
    const tool = hwc.input.Tablet.Tool.get(
        server.input_manager.seat.wlr_seat,
        tablet,
        event.tool,
    ) catch return;

    tool.button(tablet, event);
}
