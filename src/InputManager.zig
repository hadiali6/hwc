const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.input_manager);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc.zig");
const c = @import("c.zig");
const util = @import("util.zig");

var server = &@import("root").server;

seat: hwc.Seat,
devices: wl.list.Head(Device, .link),

virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,
virtual_pointer_manager: *wlr.VirtualPointerManagerV1,

new_input: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleNewInput),

new_virtual_keyboard: wl.Listener(*wlr.VirtualKeyboardV1) =
    wl.Listener(*wlr.VirtualKeyboardV1).init(handleNewVirtualKeyboard),

new_virtual_pointer: wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer) =
    wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer).init(handleNewVirtualPointer),

pub fn init(self: *hwc.InputManager) !void {
    self.* = .{
        .seat = undefined,
        .devices = undefined,
        .virtual_keyboard_manager = try wlr.VirtualKeyboardManagerV1.create(server.wl_server),
        .virtual_pointer_manager = try wlr.VirtualPointerManagerV1.create(server.wl_server),
    };

    try self.seat.init();
    self.devices.init();

    server.backend.events.new_input.add(&self.new_input);
    self.virtual_keyboard_manager.events.new_virtual_keyboard.add(&self.new_virtual_keyboard);
    self.virtual_pointer_manager.events.new_virtual_pointer.add(&self.new_virtual_pointer);
}

pub fn deinit(self: *hwc.InputManager) void {
    self.new_input.link.remove();
    self.new_virtual_keyboard.link.remove();
    self.new_virtual_pointer.link.remove();

    std.debug.assert(self.devices.empty());
    self.seat.deinit();
}

fn handleNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    wlr_input_device: *wlr.InputDevice,
) void {
    const input_manager: *hwc.InputManager = @fieldParentPtr("new_input", listener);
    input_manager.addDevice(wlr_input_device) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };
}

fn handleNewVirtualKeyboard(
    listener: *wl.Listener(*wlr.VirtualKeyboardV1),
    wlr_virtual_keyboard: *wlr.VirtualKeyboardV1,
) void {
    const input_manager: *hwc.InputManager = @fieldParentPtr("new_virtual_keyboard", listener);
    input_manager.addDevice(&wlr_virtual_keyboard.keyboard.base) catch |err| {
        log.err("{s} failed: {}", .{ @src().fn_name, err });
        return;
    };
}

fn handleNewVirtualPointer(
    listener: *wl.Listener(*wlr.VirtualPointerManagerV1.event.NewPointer),
    event: *wlr.VirtualPointerManagerV1.event.NewPointer,
) void {
    const input_manager: *hwc.InputManager = @fieldParentPtr("new_virtual_pointer", listener);

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

fn addDevice(self: *hwc.InputManager, wlr_input_device: *wlr.InputDevice) !void {
    switch (wlr_input_device.type) {
        .keyboard => {
            const keyboard = try util.allocator.create(hwc.Keyboard);

            try keyboard.init(wlr_input_device);
            errdefer keyboard.deinit();

            const seat = &server.input_manager.seat;
            seat.wlr_seat.setKeyboard(keyboard.device.wlr_input_device.toKeyboard());
            if (seat.wlr_seat.keyboard_state.focused_surface) |wlr_surface| {
                seat.keyboardNotifyEnter(wlr_surface);
            }
        },
        .pointer => {
            const device = try util.allocator.create(Device);
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

pub const Device = struct {
    wlr_input_device: *wlr.InputDevice,

    /// InputManager.devices
    link: wl.list.Link,

    /// Careful: The identifier is not unique! A physical input device may have
    /// multiple logical input devices with the exact same vendor id, product id
    /// and name. However identifiers of InputConfigs are unique.
    identifier: []const u8,

    destroy: wl.Listener(*wlr.InputDevice) =
        wl.Listener(*wlr.InputDevice).init(handleDestroy),

    pub fn init(self: *Device, wlr_input_device: *wlr.InputDevice) !void {
        self.* = .{
            .wlr_input_device = wlr_input_device,
            .link = undefined,
            .identifier = blk: {
                var vendor: c_uint = 0;
                var product: c_uint = 0;

                if (wlr_input_device.getLibinputDevice()) |libinput_device| {
                    vendor = c.libinput_device_get_id_vendor(@ptrCast(libinput_device));
                    product = c.libinput_device_get_id_product(@ptrCast(libinput_device));
                }

                const id = try std.fmt.allocPrint(util.allocator, "{s}-{}-{}-{s}", .{
                    @tagName(wlr_input_device.type),
                    vendor,
                    product,
                    std.mem.trim(
                        u8,
                        std.mem.sliceTo(wlr_input_device.name orelse "unkown", 0),
                        &std.ascii.whitespace,
                    ),
                });

                for (id) |*byte| {
                    if (!std.ascii.isPrint(byte.*) or std.ascii.isWhitespace(byte.*)) {
                        byte.* = '_';
                    }
                }

                break :blk id;
            },
        };

        wlr_input_device.data = @intFromPtr(self);
        wlr_input_device.events.destroy.add(&self.destroy);

        if (!isKeyboardGroup(self.wlr_input_device)) {
            server.input_manager.devices.append(self);
            server.input_manager.seat.updateCapabilities();
        }
    }

    pub fn deinit(self: *Device) void {
        self.destroy.link.remove();
        util.allocator.free(self.identifier);

        if (!isKeyboardGroup(self.wlr_input_device)) {
            self.link.remove();
        }

        self.wlr_input_device.data = 0;
        self.* = undefined;
    }

    fn handleDestroy(
        listener: *wl.Listener(*wlr.InputDevice),
        _: *wlr.InputDevice,
    ) void {
        const device: *Device = @fieldParentPtr("destroy", listener);

        switch (device.wlr_input_device.type) {
            .keyboard => {
                const keyboard: *hwc.Keyboard = @fieldParentPtr("device", device);
                keyboard.deinit();
            },
            .pointer => {
                device.deinit();
                util.allocator.destroy(device);
            },
            .touch, .tablet, .tablet_pad, .@"switch" => unreachable,
        }
    }

    fn isKeyboardGroup(wlr_input_device: *wlr.InputDevice) bool {
        return wlr_input_device.type == .keyboard and
            wlr.KeyboardGroup.fromKeyboard(wlr_input_device.toKeyboard()) != null;
    }
};
