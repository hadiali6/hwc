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

seats: wl.list.Head(hwc.input.Seat, .link),
devices: wl.list.Head(hwc.input.Device, .link),

keyboard_shortcuts_inhibit_manager: *wlr.KeyboardShortcutsInhibitManagerV1,
relative_pointer_manager: *wlr.RelativePointerManagerV1,
virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,
virtual_pointer_manager: *wlr.VirtualPointerManagerV1,
pointer_gestures: *wlr.PointerGesturesV1,
pointer_constraints: *wlr.PointerConstraintsV1,
idle_notifier: *wlr.IdleNotifierV1,
input_method_manager: *wlr.InputMethodManagerV2,
text_input_manager: *wlr.TextInputManagerV3,
tablet_manager: *wlr.TabletManagerV2,
transient_seat_manager: *wlr.TransientSeatManagerV1,

new_input: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleNewInput),
new_keyboard_shortcuts_inhibitor: wl.Listener(*wlr.KeyboardShortcutsInhibitorV1) =
    wl.Listener(*wlr.KeyboardShortcutsInhibitorV1).init(handleNewKeyboardShortcutsInhibitor),
new_virtual_keyboard: wl.Listener(*wlr.VirtualKeyboardV1) =
    wl.Listener(*wlr.VirtualKeyboardV1).init(handleNewVirtualKeyboard),
new_virtual_pointer: wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer) =
    wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer).init(handleNewVirtualPointer),
new_constraint: wl.Listener(*wlr.PointerConstraintV1) =
    wl.Listener(*wlr.PointerConstraintV1).init(handleNewConstraint),
new_input_method: wl.Listener(*wlr.InputMethodV2) =
    wl.Listener(*wlr.InputMethodV2).init(handleNewInputMethod),
new_text_input: wl.Listener(*wlr.TextInputV3) =
    wl.Listener(*wlr.TextInputV3).init(handleNewTextInput),
new_transient_seat: wl.Listener(*wlr.TransientSeatV1) =
    wl.Listener(*wlr.TransientSeatV1).init(handleNewTransientSeat),

pub fn init(self: *hwc.input.Manager) !void {
    self.* = .{
        .seats = undefined,
        .devices = undefined,

        .keyboard_shortcuts_inhibit_manager = try wlr.KeyboardShortcutsInhibitManagerV1.create(server.wl_server),
        .relative_pointer_manager = try wlr.RelativePointerManagerV1.create(server.wl_server),
        .virtual_keyboard_manager = try wlr.VirtualKeyboardManagerV1.create(server.wl_server),
        .virtual_pointer_manager = try wlr.VirtualPointerManagerV1.create(server.wl_server),
        .pointer_gestures = try wlr.PointerGesturesV1.create(server.wl_server),
        .pointer_constraints = try wlr.PointerConstraintsV1.create(server.wl_server),
        .idle_notifier = try wlr.IdleNotifierV1.create(server.wl_server),
        .input_method_manager = try wlr.InputMethodManagerV2.create(server.wl_server),
        .text_input_manager = try wlr.TextInputManagerV3.create(server.wl_server),
        .tablet_manager = try wlr.TabletManagerV2.create(server.wl_server),
        .transient_seat_manager = try wlr.TransientSeatManagerV1.create(server.wl_server),
    };

    self.devices.init();
    self.seats.init();

    {
        const seat = try util.allocator.create(hwc.input.Seat);
        try seat.init("default");
        self.seats.append(seat);
    }

    server.backend.events.new_input.add(&self.new_input);
    self.keyboard_shortcuts_inhibit_manager.events.new_inhibitor.add(&self.new_keyboard_shortcuts_inhibitor);
    self.virtual_keyboard_manager.events.new_virtual_keyboard.add(&self.new_virtual_keyboard);
    self.virtual_pointer_manager.events.new_virtual_pointer.add(&self.new_virtual_pointer);
    self.pointer_constraints.events.new_constraint.add(&self.new_constraint);
    self.transient_seat_manager.events.create_seat.add(&self.new_transient_seat);
}

pub fn deinit(self: *hwc.input.Manager) void {
    self.new_input.link.remove();
    self.new_virtual_keyboard.link.remove();
    self.new_virtual_pointer.link.remove();
    self.new_constraint.link.remove();

    assert(self.devices.empty());

    while (self.seats.first()) |seat| {
        seat.deinit();
    }
}

pub fn defaultSeat(self: *hwc.input.Manager) *hwc.input.Seat {
    // first seat is always the default one
    return self.seats.first().?;
}

pub fn handleActivity(self: *hwc.input.Manager) void {
    self.idle_notifier.notifyActivity(self.defaultSeat().wlr_seat);
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

fn handleNewKeyboardShortcutsInhibitor(
    _: *wl.Listener(*wlr.KeyboardShortcutsInhibitorV1),
    wlr_keyboard_shortcuts_inhibitor: *wlr.KeyboardShortcutsInhibitorV1,
) void {
    hwc.input.KeyboardShortcutsInhibitor.create(wlr_keyboard_shortcuts_inhibitor) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };

    wlr_keyboard_shortcuts_inhibitor.activate();

    if (hwc.Focusable.fromSurface(wlr_keyboard_shortcuts_inhibitor.surface)) |focusable| {
        if (focusable.* == .toplevel) {
            focusable.toplevel.keyboard_shortcuts_inhibit = true;
        }
    }
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

fn handleNewInputMethod(
    listener: *wl.Listener(*wlr.InputMethodV2),
    wlr_input_method: *wlr.InputMethodV2,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_input_method", listener);
    input_manager.defaultSeat().relay.newInputMethod(wlr_input_method);
}

fn handleNewTextInput(
    listener: *wl.Listener(*wlr.TextInputV3),
    wlr_text_input: *wlr.TextInputV3,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_text_input", listener);
    input_manager.defaultSeat().relay.newTextInput(wlr_text_input) catch {
        log.err("out of memory", .{});
        wlr_text_input.resource.postNoMemory();
        return;
    };
}

fn handleNewTransientSeat(
    listener: *wl.Listener(*wlr.TransientSeatV1),
    wlr_transient_seat: *wlr.TransientSeatV1,
) void {
    const state = struct {
        var counter: u64 = 0;
    };

    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_transient_seat", listener);

    const seat = util.allocator.create(hwc.input.Seat) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        wlr_transient_seat.deny();
        return;
    };

    seat.init(blk: {
        var buffer = [_]u8{0} ** 256;
        const name = std.fmt.bufPrintZ(&buffer, "transient-{}", .{state.counter}) catch |err| {
            log.err("{s} failed: {}", .{ @src().fn_name, err });
            wlr_transient_seat.deny();
            return;
        };

        break :blk name;
    }) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        wlr_transient_seat.deny();
        return;
    };

    input_manager.seats.append(seat);
    state.counter += 1;

    wlr_transient_seat.ready(seat.wlr_seat);
}

pub fn addDevice(self: *hwc.input.Manager, wlr_input_device: *wlr.InputDevice) !void {
    switch (wlr_input_device.type) {
        .keyboard => {
            const keyboard = try util.allocator.create(hwc.input.Keyboard);

            try keyboard.init(wlr_input_device);
            errdefer keyboard.deinit();

            const seat = self.defaultSeat();
            seat.wlr_seat.setKeyboard(keyboard.device.wlr_input_device.toKeyboard());
            if (seat.wlr_seat.keyboard_state.focused_surface) |wlr_surface| {
                seat.keyboardNotifyEnter(wlr_surface);
            }
        },
        .touch, .pointer => {
            const device = try util.allocator.create(hwc.input.Device);
            errdefer {
                device.deinit();
                util.allocator.destroy(device);
            }

            try device.init(wlr_input_device);
            self.defaultSeat().cursor.wlr_cursor.attachInputDevice(wlr_input_device);
        },
        .tablet => {
            const tablet = try util.allocator.create(hwc.input.Tablet);

            try tablet.init(wlr_input_device);
            errdefer tablet.deinit();

            self.defaultSeat().cursor.wlr_cursor.attachInputDevice(wlr_input_device);
        },
        .tablet_pad => {
            const tablet_pad = try util.allocator.create(hwc.input.Tablet.Pad);

            try tablet_pad.init(wlr_input_device);
            errdefer tablet_pad.deinit();
        },
        .@"switch" => {
            const switch_device = try util.allocator.create(hwc.input.Switch);

            try switch_device.init(wlr_input_device);
            errdefer switch_device.deinit();
        },
    }
}
