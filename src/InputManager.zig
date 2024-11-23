const std = @import("std");
const log = std.log.scoped(.input_manager);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc.zig");

var server = &@import("root").server;

seat: hwc.Seat,
all_keyboards: wl.list.Head(hwc.Keyboard, .link),

new_input: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleNewInput),

pub fn init(self: *hwc.InputManager) !void {
    self.* = .{
        .seat = undefined,
        .all_keyboards = undefined,
    };
    try self.seat.init();
    self.all_keyboards.init();

    server.backend.events.new_input.add(&self.new_input);
}

pub fn deinit(self: *hwc.InputManager) void {
    self.seat.deinit();
}

fn handleNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    device: *wlr.InputDevice,
) void {
    const input_manager: *hwc.InputManager = @fieldParentPtr("new_input", listener);
    switch (device.type) {
        .keyboard => hwc.Keyboard.create(device) catch |err| {
            log.err("failed to create keyboard: {}", .{err});
            return;
        },
        .pointer => input_manager.seat.cursor.wlr_cursor.attachInputDevice(device),
        else => {},
    }

    input_manager.seat.wlr_seat.setCapabilities(.{
        .pointer = true,
        .keyboard = input_manager.all_keyboards.length() > 0,
    });
}
