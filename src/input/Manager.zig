const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.input_manager);
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const c = @import("../c.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

seat: hwc.input.Seat,
devices: wl.list.Head(hwc.input.Device, .link),

relative_pointer_manager: *wlr.RelativePointerManagerV1,
virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,
virtual_pointer_manager: *wlr.VirtualPointerManagerV1,
pointer_gestures: *wlr.PointerGesturesV1,
pointer_constraints: *wlr.PointerConstraintsV1,

new_input: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleNewInput),
new_virtual_keyboard: wl.Listener(*wlr.VirtualKeyboardV1) =
    wl.Listener(*wlr.VirtualKeyboardV1).init(handleNewVirtualKeyboard),
new_virtual_pointer: wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer) =
    wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer).init(handleNewVirtualPointer),
new_constraint: wl.Listener(*wlr.PointerConstraintV1) =
    wl.Listener(*wlr.PointerConstraintV1).init(handleNewConstraint),

pub fn init(self: *hwc.input.Manager) !void {
    self.* = .{
        .seat = undefined,
        .devices = undefined,
        .relative_pointer_manager = try wlr.RelativePointerManagerV1.create(server.wl_server),
        .virtual_keyboard_manager = try wlr.VirtualKeyboardManagerV1.create(server.wl_server),
        .virtual_pointer_manager = try wlr.VirtualPointerManagerV1.create(server.wl_server),
        .pointer_gestures = try wlr.PointerGesturesV1.create(server.wl_server),
        .pointer_constraints = try wlr.PointerConstraintsV1.create(server.wl_server),
    };

    try self.seat.init();
    self.devices.init();

    server.backend.events.new_input.add(&self.new_input);
    self.virtual_keyboard_manager.events.new_virtual_keyboard.add(&self.new_virtual_keyboard);
    self.virtual_pointer_manager.events.new_virtual_pointer.add(&self.new_virtual_pointer);
    self.pointer_constraints.events.new_constraint.add(&self.new_constraint);
}

pub fn deinit(self: *hwc.input.Manager) void {
    self.new_input.link.remove();
    self.new_virtual_keyboard.link.remove();
    self.new_virtual_pointer.link.remove();
    self.new_constraint.link.remove();

    assert(self.devices.empty());
    self.seat.deinit();
}

fn handleNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    wlr_input_device: *wlr.InputDevice,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_input", listener);
    input_manager.addDevice(wlr_input_device) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };
}

fn handleNewVirtualKeyboard(
    listener: *wl.Listener(*wlr.VirtualKeyboardV1),
    wlr_virtual_keyboard: *wlr.VirtualKeyboardV1,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_virtual_keyboard", listener);
    input_manager.addDevice(&wlr_virtual_keyboard.keyboard.base) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };
}

fn handleNewVirtualPointer(
    listener: *wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer),
    event: *wlr.VirtualPointerManagerV1.event.NewPointer,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_virtual_pointer", listener);

    if (event.suggested_seat) |wlr_seat| {
        log.debug("{s} suggested_seat: {*}", .{ @src().fn_name, wlr_seat });
        log.info("ignoring seat suggestion from virtual pointer", .{});
    }

    if (event.suggested_output) |wlr_output| {
        log.debug("{s} suggested_output: {*}", .{ @src().fn_name, wlr_output });
        log.info("ignoring output suggestion from virtual pointer", .{});
    }

    input_manager.addDevice(&event.new_pointer.pointer.base) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };
}

fn handleNewConstraint(
    _: *wl.Listener(*wlr.PointerConstraintV1),
    wlr_pointer_constraint: *wlr.PointerConstraintV1,
) void {
    hwc.input.PointerConstraint.create(wlr_pointer_constraint) catch {
        wlr_pointer_constraint.resource.postNoMemory();
    };
}

fn addDevice(self: *hwc.input.Manager, wlr_input_device: *wlr.InputDevice) !void {
    switch (wlr_input_device.type) {
        .keyboard => {
            const keyboard = try util.allocator.create(hwc.input.Keyboard);

            try keyboard.init(wlr_input_device);
            errdefer keyboard.deinit();

            const seat = &server.input_manager.seat;
            seat.wlr_seat.setKeyboard(keyboard.device.wlr_input_device.toKeyboard());
            if (seat.wlr_seat.keyboard_state.focused_surface) |wlr_surface| {
                seat.keyboardNotifyEnter(wlr_surface);
            }
        },
        .pointer => {
            const device = try util.allocator.create(hwc.input.Device);
            errdefer {
                device.deinit();
                util.allocator.destroy(device);
            }

            try device.init(wlr_input_device);
            self.seat.cursor.wlr_cursor.attachInputDevice(wlr_input_device);
        },
        .touch, .tablet, .tablet_pad, .@"switch" => |device_type| {
            log.warn("detected unsopported device: {s}", .{@tagName(device_type)});
        },
    }
}
