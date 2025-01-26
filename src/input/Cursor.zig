const std = @import("std");
const log = std.log.scoped(.@"input.Cursor");
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

wlr_cursor: *wlr.Cursor,
wlr_xcursor_manager: *wlr.XcursorManager,

axis: wl.Listener(*wlr.Pointer.event.Axis) = wl.Listener(*wlr.Pointer.event.Axis).init(handleAxis),
button: wl.Listener(*wlr.Pointer.event.Button) =
    wl.Listener(*wlr.Pointer.event.Button).init(handleButton),
frame: wl.Listener(*wlr.Cursor) = wl.Listener(*wlr.Cursor).init(handleFrame),
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

touch_up: wl.Listener(*wlr.Touch.event.Up) = wl.Listener(*wlr.Touch.event.Up).init(handleTouchUp),
touch_down: wl.Listener(*wlr.Touch.event.Down) =
    wl.Listener(*wlr.Touch.event.Down).init(handleTouchDown),
touch_motion: wl.Listener(*wlr.Touch.event.Motion) =
    wl.Listener(*wlr.Touch.event.Motion).init(handleTouchMotion),
touch_cancel: wl.Listener(*wlr.Touch.event.Cancel) =
    wl.Listener(*wlr.Touch.event.Cancel).init(handleTouchCancel),
touch_frame: wl.Listener(void) = wl.Listener(void).init(handleTouchFrame),

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
        .wlr_xcursor_manager = try wlr.XcursorManager.create(null, 24),
    };

    self.wlr_cursor.attachOutputLayout(server.output_manager.wlr_output_layout);
    try self.wlr_xcursor_manager.load(1);

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

    log.info(
        "{s}: xcursor_manager_name='{s}' xcursor_name='{s}'",
        .{
            @src().fn_name,
            self.wlr_xcursor_manager.name orelse "unknown",
            self.wlr_xcursor_manager.getXcursor("default", 1).?.name,
        },
    );
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

    log.info(
        "{s}: xcursor_manager_name='{s}' xcursor_name='{s}'",
        .{
            @src().fn_name,
            self.wlr_xcursor_manager.name orelse "unknown",
            self.wlr_xcursor_manager.getXcursor("default", 1).?.name,
        },
    );

    self.wlr_cursor.destroy();
    self.wlr_xcursor_manager.destroy();
}

fn getSeat(self: *hwc.input.Cursor) *hwc.input.Seat {
    return @fieldParentPtr("cursor", self);
}

fn handleAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("axis", listener);
    const seat = cursor.getSeat();

    seat.wlr_seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );

    log.debug("{s}: {*}", .{ @src().fn_name, cursor });
}

fn handleButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("button", listener);
    _ = event;

    log.debug("{s}: {*}", .{ @src().fn_name, cursor });
}

fn handleFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("frame", listener);
    const seat = cursor.getSeat();

    seat.wlr_seat.pointerNotifyFrame();
}

fn handleMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion", listener);
    _ = event;

    log.debug("{s}: {*}", .{ @src().fn_name, cursor });
}

fn handleMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion_absolute", listener);
    _ = cursor;
    _ = event;
}

fn handlePinchBegin(
    listener: *wl.Listener(*wlr.Pointer.event.PinchBegin),
    event: *wlr.Pointer.event.PinchBegin,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("pinch_begin", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendPinchBegin(seat.wlr_seat, event.time_msec, event.fingers);
}

fn handlePinchUpdate(
    listener: *wl.Listener(*wlr.Pointer.event.PinchUpdate),
    event: *wlr.Pointer.event.PinchUpdate,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("pinch_update", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendPinchUpdate(
        seat.wlr_seat,
        event.time_msec,
        event.dx,
        event.dy,
        event.scale,
        event.rotation,
    );
}

fn handlePinchEnd(
    listener: *wl.Listener(*wlr.Pointer.event.PinchEnd),
    event: *wlr.Pointer.event.PinchEnd,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("pinch_end", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendPinchEnd(
        seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleSwipeBegin(
    listener: *wl.Listener(*wlr.Pointer.event.SwipeBegin),
    event: *wlr.Pointer.event.SwipeBegin,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("swipe_begin", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendSwipeBegin(
        seat.wlr_seat,
        event.time_msec,
        event.fingers,
    );
}

fn handleSwipeUpdate(
    listener: *wl.Listener(*wlr.Pointer.event.SwipeUpdate),
    event: *wlr.Pointer.event.SwipeUpdate,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("swipe_update", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendSwipeUpdate(
        seat.wlr_seat,
        event.time_msec,
        event.dx,
        event.dy,
    );
}

fn handleSwipeEnd(
    listener: *wl.Listener(*wlr.Pointer.event.SwipeEnd),
    event: *wlr.Pointer.event.SwipeEnd,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("swipe_end", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendPinchEnd(
        seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleHoldBegin(
    listener: *wl.Listener(*wlr.Pointer.event.HoldBegin),
    event: *wlr.Pointer.event.HoldBegin,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("hold_begin", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendHoldBegin(
        seat.wlr_seat,
        event.time_msec,
        event.fingers,
    );
}

fn handleHoldEnd(
    listener: *wl.Listener(*wlr.Pointer.event.HoldEnd),
    event: *wlr.Pointer.event.HoldEnd,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("hold_end", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendHoldEnd(
        seat.wlr_seat,
        event.time_msec,
        event.cancelled,
    );
}

fn handleTouchUp(
    listener: *wl.Listener(*wlr.Touch.event.Up),
    event: *wlr.Touch.event.Up,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_up", listener);
    _ = cursor;
    _ = event;
}

fn handleTouchDown(
    listener: *wl.Listener(*wlr.Touch.event.Down),
    event: *wlr.Touch.event.Down,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_down", listener);
    _ = cursor;
    _ = event;
}

fn handleTouchMotion(
    listener: *wl.Listener(*wlr.Touch.event.Motion),
    event: *wlr.Touch.event.Motion,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_motion", listener);
    _ = cursor;
    _ = event;
}

fn handleTouchCancel(
    listener: *wl.Listener(*wlr.Touch.event.Cancel),
    event: *wlr.Touch.event.Cancel,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_cancel", listener);
    _ = cursor;
    _ = event;
}

fn handleTouchFrame(listener: *wl.Listener(void)) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_frame", listener);
    const seat = cursor.getSeat();

    seat.wlr_seat.touchNotifyFrame();
}

fn handleTabletToolAxis(
    listener: *wl.Listener(*wlr.Tablet.event.Axis),
    event: *wlr.Tablet.event.Axis,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_axis", listener);
    _ = cursor;
    _ = event;
}

fn handleTabletToolProximity(
    listener: *wl.Listener(*wlr.Tablet.event.Proximity),
    event: *wlr.Tablet.event.Proximity,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_proximity", listener);
    _ = cursor;
    _ = event;
}
fn handleTabletToolTip(
    listener: *wl.Listener(*wlr.Tablet.event.Tip),
    event: *wlr.Tablet.event.Tip,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_tip", listener);
    _ = cursor;
    _ = event;
}
fn handleTabletToolButton(
    listener: *wl.Listener(*wlr.Tablet.event.Button),
    event: *wlr.Tablet.event.Button,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_button", listener);
    _ = cursor;
    _ = event;
}
