const std = @import("std");
const log = std.log.scoped(.@"input.Cursor");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

const ImageName = enum {
    default,
    move,
    @"n-resize",
    @"nw-resize",
    @"ne-resize",
    @"s-resize",
    @"sw-resize",
    @"se-resize",
    @"w-resize",
    @"e-resize",
};

wlr_cursor: *wlr.Cursor,
wlr_xcursor_manager: *wlr.XcursorManager,

mode: union(enum) {
    passthrough,
    move: *hwc.desktop.XdgToplevel,
    resize: *hwc.desktop.XdgToplevel,
} = .passthrough,

grab_x: f64 = 0,
grab_y: f64 = 0,
grab_box: wlr.Box = undefined,
resize_edges: wlr.Edges = .{},

frame: wl.Listener(*wlr.Cursor) = wl.Listener(*wlr.Cursor).init(handleFrame),

axis: wl.Listener(*wlr.Pointer.event.Axis) =
    wl.Listener(*wlr.Pointer.event.Axis).init(handlePointerAxis),
button: wl.Listener(*wlr.Pointer.event.Button) =
    wl.Listener(*wlr.Pointer.event.Button).init(handlePointerButton),
motion: wl.Listener(*wlr.Pointer.event.Motion) =
    wl.Listener(*wlr.Pointer.event.Motion).init(handlePointerMotion),
motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) =
    wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(handlePointerMotionAbsolute),

pinch_begin: wl.Listener(*wlr.Pointer.event.PinchBegin) =
    wl.Listener(*wlr.Pointer.event.PinchBegin).init(handlePointerPinchBegin),
pinch_update: wl.Listener(*wlr.Pointer.event.PinchUpdate) =
    wl.Listener(*wlr.Pointer.event.PinchUpdate).init(handlePointerPinchUpdate),
pinch_end: wl.Listener(*wlr.Pointer.event.PinchEnd) =
    wl.Listener(*wlr.Pointer.event.PinchEnd).init(handlePointerPinchEnd),

swipe_begin: wl.Listener(*wlr.Pointer.event.SwipeBegin) =
    wl.Listener(*wlr.Pointer.event.SwipeBegin).init(handlePointerSwipeBegin),
swipe_update: wl.Listener(*wlr.Pointer.event.SwipeUpdate) =
    wl.Listener(*wlr.Pointer.event.SwipeUpdate).init(handlePointerSwipeUpdate),
swipe_end: wl.Listener(*wlr.Pointer.event.SwipeEnd) =
    wl.Listener(*wlr.Pointer.event.SwipeEnd).init(handlePointerSwipeEnd),

hold_begin: wl.Listener(*wlr.Pointer.event.HoldBegin) =
    wl.Listener(*wlr.Pointer.event.HoldBegin).init(handlePointerHoldBegin),
hold_end: wl.Listener(*wlr.Pointer.event.HoldEnd) =
    wl.Listener(*wlr.Pointer.event.HoldEnd).init(handlePointerHoldEnd),

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

    log.info("{s}", .{@src().fn_name});
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

    log.info("{s}", .{@src().fn_name});

    self.wlr_cursor.destroy();
    self.wlr_xcursor_manager.destroy();
}

fn getSeat(self: *hwc.input.Cursor) *hwc.input.Seat {
    return @fieldParentPtr("cursor", self);
}

fn handleFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("frame", listener);
    const seat = cursor.getSeat();
    seat.wlr_seat.pointerNotifyFrame();
}

fn handlePointerAxis(
    listener: *wl.Listener(*wlr.Pointer.event.Axis),
    event: *wlr.Pointer.event.Axis,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("axis", listener);
    const seat = cursor.getSeat();

    // TODO pointer scroll wheel binding

    seat.wlr_seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
        event.relative_direction,
    );

    log.debug(
        "{s}: device='{s}' scroll='{s}' orientation='{s}' source='{s}' relative_direction='{s}'",
        .{
            @src().fn_name,
            hwc.input.Device.fromWlrInputDevice(event.device).identifier,
            if (event.delta_discrete > 0) "down" else "up",
            @tagName(event.orientation),
            @tagName(event.source),
            @tagName(event.relative_direction),
        },
    );
}

fn handlePointerButton(
    listener: *wl.Listener(*wlr.Pointer.event.Button),
    event: *wlr.Pointer.event.Button,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("button", listener);
    const seat = cursor.getSeat();

    // TODO pointer button binding

    _ = seat.wlr_seat.pointerNotifyButton(event.time_msec, event.button, event.state);
    switch (event.state) {
        .released => {
            cursor.mode = .passthrough;
        },

        .pressed => if (server.surface_manager.resultAt(
            cursor.wlr_cursor.x,
            cursor.wlr_cursor.y,
        )) |result| {
            std.debug.print(
                "{?*} {*} {} {}\n",
                .{ result.wlr_surface, result.wlr_scene_node, result.sx, result.sy },
            );
            if (hwc.desktop.SceneDescriptor.fromNode(result.wlr_scene_node)) |scene_descriptor| {
                seat.focus(scene_descriptor.focusable);
            }
        },

        else => unreachable,
    }

    log.debug("{s}: device='{s}' button='{?s}' state='{s}'", .{
        @src().fn_name,
        hwc.input.Device.fromWlrInputDevice(event.device).identifier,
        hwc.input.util.linuxInputEventCodeToString(.pointer, event.button),
        @tagName(event.state),
    });
}

// TODO (bad)
fn handlePointerMotion(
    listener: *wl.Listener(*wlr.Pointer.event.Motion),
    event: *wlr.Pointer.event.Motion,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion", listener);

    if (server.output_manager.wlr_output_layout.outputAt(
        cursor.wlr_cursor.x,
        cursor.wlr_cursor.y,
    )) |wlr_output| {
        const output = hwc.desktop.Output.fromWlrOutput(wlr_output);
        const seat = cursor.getSeat();
        seat.focusOutput(output);
    }

    cursor.processMotion(
        event.device,
        event.time_msec,
        event.delta_x,
        event.delta_y,
        event.unaccel_dx,
        event.unaccel_dy,
    );
}

// TODO (bad)
fn handlePointerMotionAbsolute(
    listener: *wl.Listener(*wlr.Pointer.event.MotionAbsolute),
    event: *wlr.Pointer.event.MotionAbsolute,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("motion_absolute", listener);

    var lx: f64 = undefined;
    var ly: f64 = undefined;
    cursor.wlr_cursor.absoluteToLayoutCoords(event.device, event.x, event.y, &lx, &ly);

    const dx = lx - cursor.wlr_cursor.x;
    const dy = ly - cursor.wlr_cursor.y;

    cursor.processMotion(event.device, event.time_msec, dx, dy, dx, dy);
}

// TODO (bad)
fn processMotion(
    self: *hwc.input.Cursor,
    wlr_input_device: *wlr.InputDevice,
    time_msec: u32,
    delta_x: f64,
    delta_y: f64,
    unaccel_dx: f64,
    unaccel_dy: f64,
) void {
    const seat = self.getSeat();

    server.input_manager.wlr_relative_pointer_manager.sendRelativeMotion(
        seat.wlr_seat,
        @as(u64, time_msec) * 1000,
        delta_x,
        delta_y,
        unaccel_dx,
        unaccel_dy,
    );

    self.wlr_cursor.move(wlr_input_device, delta_x, delta_y);
    switch (self.mode) {
        .passthrough => {
            self.passthrough(time_msec);
        },
        .move => |toplevel| self.move(toplevel),
        .resize => |toplevel| self.resize(toplevel),
    }
}

// TODO (bad)
fn passthrough(self: *hwc.input.Cursor, time_msec: u32) void {
    const seat = self.getSeat();

    if (server.surface_manager.resultAt(self.wlr_cursor.x, self.wlr_cursor.y)) |result| {
        if (result.wlr_surface) |wlr_surface| {
            seat.wlr_seat.pointerNotifyEnter(wlr_surface, result.sx, result.sy);
            seat.wlr_seat.pointerNotifyMotion(time_msec, result.sx, result.sy);
        } else unreachable;

        return;
    }

    self.wlr_cursor.setXcursor(self.wlr_xcursor_manager, "default");
    seat.wlr_seat.pointerClearFocus();
}

// TODO (bad)
fn move(self: *hwc.input.Cursor, toplevel: *hwc.desktop.XdgToplevel) void {
    toplevel.x = @as(i32, @intFromFloat(self.wlr_cursor.x - self.grab_x));
    toplevel.y = @as(i32, @intFromFloat(self.wlr_cursor.y - self.grab_y));

    toplevel.popup_tree.node.setPosition(toplevel.x, toplevel.y);
    toplevel.surface_tree.node.setPosition(toplevel.x, toplevel.y);
}

// TODO (bad)
fn resize(self: *hwc.input.Cursor, toplevel: *hwc.desktop.XdgToplevel) void {
    const border_x = @as(i32, @intFromFloat(self.wlr_cursor.x - self.grab_x));
    const border_y = @as(i32, @intFromFloat(self.wlr_cursor.y - self.grab_y));

    var new_left = self.grab_box.x;
    var new_right = self.grab_box.x + self.grab_box.width;
    var new_top = self.grab_box.y;
    var new_bottom = self.grab_box.y + self.grab_box.height;

    if (self.resize_edges.top) {
        new_top = border_y;
        if (new_top >= new_bottom) {
            new_top = new_bottom - 1;
        }
    } else if (self.resize_edges.bottom) {
        new_bottom = border_y;
        if (new_bottom <= new_top) {
            new_bottom = new_top + 1;
        }
    }

    if (self.resize_edges.left) {
        new_left = border_x;
        if (new_left >= new_right) {
            new_left = new_right - 1;
        }
    } else if (self.resize_edges.right) {
        new_right = border_x;
        if (new_right <= new_left) {
            new_right = new_left + 1;
        }
    }

    var geo_box: wlr.Box = undefined;
    toplevel.wlr_xdg_toplevel.base.getGeometry(&geo_box);
    toplevel.x = new_left - geo_box.x;
    toplevel.y = new_top - geo_box.y;
    toplevel.surface_tree.node.setPosition(toplevel.x, toplevel.y);
    toplevel.popup_tree.node.setPosition(toplevel.x, toplevel.y);

    const new_width = new_right - new_left;
    const new_height = new_bottom - new_top;
    _ = toplevel.wlr_xdg_toplevel.setSize(new_width, new_height);
}

fn handlePointerPinchBegin(
    listener: *wl.Listener(*wlr.Pointer.event.PinchBegin),
    event: *wlr.Pointer.event.PinchBegin,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("pinch_begin", listener);
    const seat = cursor.getSeat();
    const wlr_pointer_gestures = server.input_manager.wlr_pointer_gestures;

    wlr_pointer_gestures.sendPinchBegin(seat.wlr_seat, event.time_msec, event.fingers);
}

fn handlePointerPinchUpdate(
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

fn handlePointerPinchEnd(
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

fn handlePointerSwipeBegin(
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

fn handlePointerSwipeUpdate(
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

fn handlePointerSwipeEnd(
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

fn handlePointerHoldBegin(
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

fn handlePointerHoldEnd(
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

// TODO
fn handleTouchUp(
    listener: *wl.Listener(*wlr.Touch.event.Up),
    event: *wlr.Touch.event.Up,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_up", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTouchDown(
    listener: *wl.Listener(*wlr.Touch.event.Down),
    event: *wlr.Touch.event.Down,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_down", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTouchMotion(
    listener: *wl.Listener(*wlr.Touch.event.Motion),
    event: *wlr.Touch.event.Motion,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_motion", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTouchCancel(
    listener: *wl.Listener(*wlr.Touch.event.Cancel),
    event: *wlr.Touch.event.Cancel,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_cancel", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTouchFrame(listener: *wl.Listener(void)) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("touch_frame", listener);
    const seat = cursor.getSeat();

    seat.wlr_seat.touchNotifyFrame();
}

// TODO
fn handleTabletToolAxis(
    listener: *wl.Listener(*wlr.Tablet.event.Axis),
    event: *wlr.Tablet.event.Axis,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_axis", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTabletToolProximity(
    listener: *wl.Listener(*wlr.Tablet.event.Proximity),
    event: *wlr.Tablet.event.Proximity,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_proximity", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTabletToolTip(
    listener: *wl.Listener(*wlr.Tablet.event.Tip),
    event: *wlr.Tablet.event.Tip,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_tip", listener);
    _ = cursor;
    _ = event;
}

// TODO
fn handleTabletToolButton(
    listener: *wl.Listener(*wlr.Tablet.event.Button),
    event: *wlr.Tablet.event.Button,
) void {
    const cursor: *hwc.input.Cursor = @fieldParentPtr("tablet_tool_button", listener);
    _ = cursor;
    _ = event;
}
