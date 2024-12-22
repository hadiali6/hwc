const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.input_manager);
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const libinput = @import("libinput");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

wlr_input_device: *wlr.InputDevice,

/// InputManager.devices
link: wl.list.Link,

/// Careful: The identifier is not unique! A physical input device may have
/// multiple logical input devices with the exact same vendor id, product id
/// and name. However identifiers of InputConfigs are unique.
identifier: []const u8,

destroy: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleDestroy),

pub fn init(self: *hwc.input.Device, wlr_input_device: *wlr.InputDevice) !void {
    self.* = .{
        .wlr_input_device = wlr_input_device,
        .link = undefined,
        .identifier = blk: {
            var vendor: c_uint = 0;
            var product: c_uint = 0;

            if (@as(
                ?*libinput.Device,
                @alignCast(@ptrCast(wlr_input_device.getLibinputDevice())),
            )) |libinput_device| {
                vendor = libinput_device.getVendorId();
                product = libinput_device.getProductId();
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

pub fn deinit(self: *hwc.input.Device) void {
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
    const device: *hwc.input.Device = @fieldParentPtr("destroy", listener);

    switch (device.wlr_input_device.type) {
        .keyboard => {
            const keyboard: *hwc.input.Keyboard = @fieldParentPtr("device", device);
            keyboard.deinit();
        },
        .touch, .pointer => {
            device.deinit();
            util.allocator.destroy(device);
        },
        .tablet => {
            const tablet: *hwc.input.Tablet = @fieldParentPtr("device", device);
            tablet.deinit();
        },
        .tablet_pad => {
            const tablet_pad: *hwc.input.Tablet.Pad = @fieldParentPtr("device", device);
            tablet_pad.deinit();
        },
        .@"switch" => {
            const switch_device: *hwc.input.Switch = @fieldParentPtr("device", device);
            switch_device.deinit();
        },
    }
}

fn isKeyboardGroup(wlr_input_device: *wlr.InputDevice) bool {
    return wlr_input_device.type == .keyboard and
        wlr.KeyboardGroup.fromKeyboard(wlr_input_device.toKeyboard()) != null;
}
