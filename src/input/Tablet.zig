const std = @import("std");
const log = std.log.scoped(.input_tablet);
const assert = std.debug.assert;
const math = std.math;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

device: hwc.input.Device,
wp_tablet: *wlr.TabletV2Tablet,

pub fn init(self: *hwc.input.Tablet, wlr_input_device: *wlr.InputDevice) !void {
    const input_manager = server.input_manager;

    self.* = .{
        .device = undefined,
        .wp_tablet = try input_manager.tablet_manager.createTabletV2Tablet(
            input_manager.seat.wlr_seat,
            wlr_input_device,
        ),
    };

    try self.device.init(wlr_input_device);
    errdefer self.device.deinit();
}

pub fn deinit(self: *hwc.input.Tablet) void {
    self.device.deinit();
    util.allocator.destroy(self);
}

pub const Tool = struct {
    const Mode = union(enum) {
        passthrough,
        down: struct {
            // Initial cursor position in layout coordinates
            lx: f64,
            ly: f64,
            // Initial cursor position in surface-local coordinates
            sx: f64,
            sy: f64,
        },
    };

    wp_tool: *wlr.TabletV2TabletTool,
    tilt_x: f64 = 0,
    tilt_y: f64 = 0,
    mode: Mode = .passthrough,

    set_cursor: wl.Listener(*wlr.TabletV2TabletTool.event.SetCursor) =
        wl.Listener(*wlr.TabletV2TabletTool.event.SetCursor).init(handleSetCursor),
    destroy: wl.Listener(*wlr.TabletTool) = wl.Listener(*wlr.TabletTool).init(handleDestroy),

    pub fn get(wlr_seat: *wlr.Seat, wlr_tablet_tool: *wlr.TabletTool) !*Tool {
        if (@as(?*Tool, @ptrFromInt(wlr_tablet_tool.data))) |tool| {
            return tool;
        } else {
            return create(wlr_seat, wlr_tablet_tool);
        }
    }

    fn create(wlr_seat: *wlr.Seat, wlr_tablet_tool: *wlr.TabletTool) !*Tool {
        const tool = try util.allocator.create(Tool);
        errdefer util.allocator.destroy(tool);

        tool.* = .{
            .wp_tool = try server.input_manager.tablet_manager.createTabletV2TabletTool(
                wlr_seat,
                wlr_tablet_tool,
            ),
        };

        wlr_tablet_tool.data = @intFromPtr(tool);

        tool.wp_tool.events.set_cursor.add(&tool.set_cursor);
        wlr_tablet_tool.events.destroy.add(&tool.destroy);

        return tool;
    }

    fn handleSetCursor(
        _: *wl.Listener(*wlr.TabletV2TabletTool.event.SetCursor),
        event: *wlr.TabletV2TabletTool.event.SetCursor,
    ) void {
        log.debug("set_cursor", .{});

        const seat = &server.input_manager.seat;

        if (seat.cursor.mode != .passthrough) {
            return;
        }

        if (seat.wlr_seat.pointer_state.focused_client) |wlr_seat_client| {
            if (event.seat_client != wlr_seat_client) {
                return;
            }
        }

        seat.cursor.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    }

    fn handleDestroy(listener: *wl.Listener(*wlr.TabletTool), _: *wlr.TabletTool) void {
        const tool: *Tool = @fieldParentPtr("destroy", listener);

        tool.wp_tool.wlr_tool.data = 0;

        tool.set_cursor.link.remove();
        tool.destroy.link.remove();

        util.allocator.destroy(tool);
    }

    pub fn axis(self: *Tool, tablet: *hwc.input.Tablet, event: *wlr.Tablet.event.Axis) void {
        const wlr_cursor = server.input_manager.seat.cursor.wlr_cursor;
        wlr_cursor.attachInputDevice(tablet.device.wlr_input_device);

        if (event.updated_axes.x or event.updated_axes.y) {
            switch (self.wp_tool.wlr_tool.type) {
                .pen, .eraser, .brush, .pencil, .airbrush, .totem => {
                    wlr_cursor.warpAbsolute(
                        tablet.wp_tablet.wlr_device,
                        if (event.updated_axes.x) event.x else math.nan(f64),
                        if (event.updated_axes.y) event.y else math.nan(f64),
                    );
                },
                .mouse, .lens => {
                    wlr_cursor.move(tablet.device.wlr_input_device, event.dx, event.dy);
                },
            }
            switch (self.mode) {
                .passthrough => {
                    self.passthrough(tablet);
                },
                .down => |data| {
                    self.wp_tool.notifyMotion(
                        data.sx + (wlr_cursor.x - data.lx),
                        data.sy + (wlr_cursor.y - data.ly),
                    );
                },
            }
        }

        if (event.updated_axes.distance) {
            self.wp_tool.notifyDistance(event.distance);
        }
        if (event.updated_axes.pressure) {
            self.wp_tool.notifyPressure(event.pressure);
        }
        if (event.updated_axes.tilt_x or event.updated_axes.tilt_y) {
            if (event.updated_axes.tilt_x) self.tilt_x = event.tilt_x;
            if (event.updated_axes.tilt_y) self.tilt_y = event.tilt_y;

            self.wp_tool.notifyTilt(self.tilt_x, self.tilt_y);
        }
        if (event.updated_axes.rotation) {
            self.wp_tool.notifyRotation(event.rotation);
        }
        if (event.updated_axes.slider) {
            self.wp_tool.notifySlider(event.slider);
        }
        if (event.updated_axes.wheel) {
            self.wp_tool.notifyWheel(event.wheel_delta, 0);
        }
    }

    pub fn proximity(
        self: *Tool,
        tablet: *hwc.input.Tablet,
        event: *wlr.Tablet.event.Proximity,
    ) void {
        const wlr_cursor = server.input_manager.seat.cursor.wlr_cursor;

        switch (event.state) {
            .out => {
                wlr_cursor.attachInputDevice(tablet.device.wlr_input_device);

                wlr_cursor.warpAbsolute(tablet.device.wlr_input_device, event.x, event.y);
                wlr_cursor.setXcursor(server.input_manager.seat.cursor.xcursor_manager, "pencil");

                self.passthrough(tablet);
            },
            .in => {
                self.wp_tool.notifyProximityOut();
                wlr_cursor.unsetImage();
            },
        }
    }

    pub fn tip(self: *Tool, tablet: *hwc.input.Tablet, event: *wlr.Tablet.event.Tip) void {
        const wlr_cursor = server.input_manager.seat.cursor.wlr_cursor;

        switch (event.state) {
            .down => {
                assert(!self.wp_tool.is_down);

                self.wp_tool.notifyDown();

                if (server.toplevelAt(wlr_cursor.x, wlr_cursor.y)) |result| {
                    self.mode = .{
                        .down = .{
                            .lx = wlr_cursor.x,
                            .ly = wlr_cursor.y,
                            .sx = result.sx,
                            .sy = result.sy,
                        },
                    };
                }
            },
            .up => {
                assert(self.wp_tool.is_down);

                self.wp_tool.notifyUp();
                self.maybeExitDown(tablet);
            },
        }
    }

    pub fn button(self: *Tool, tablet: *hwc.input.Tablet, event: *wlr.Tablet.event.Button) void {
        self.wp_tool.notifyButton(event.button, event.state);
        self.maybeExitDown(tablet);
    }

    /// Exit down mode if the tool is up and there are no buttons pressed
    pub fn maybeExitDown(self: *Tool, tablet: *hwc.input.Tablet) void {
        if (self.mode != .down or self.wp_tool.is_down or self.wp_tool.num_buttons > 0) {
            return;
        }

        self.mode = .passthrough;
        self.passthrough(tablet);
    }

    /// Send a motion event for the surface under the tablet tool's cursor if any.
    /// Send a proximity_in event first if needed.
    /// If there is no surface under the cursor or the surface under the cursor
    /// does not support the tablet v2 protocol, send a proximity_out event.
    fn passthrough(self: *Tool, tablet: *hwc.input.Tablet) void {
        const wlr_cursor = server.input_manager.seat.cursor.wlr_cursor;

        if (server.toplevelAt(wlr_cursor.x, wlr_cursor.y)) |result| {
            self.wp_tool.notifyProximityIn(tablet.wp_tablet, result.surface);
            self.wp_tool.notifyMotion(result.sx, result.sy);
            return;
        } else {
            wlr_cursor.setXcursor(server.input_manager.seat.cursor.xcursor_manager, "pencil");
        }

        self.wp_tool.notifyProximityOut();
    }
};
