const std = @import("std");
const log = std.log.scoped(.@"input.Device");
const assert = std.debug.assert;
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const libinput = @import("libinput");

const hwc = @import("root");
const server = &hwc.server;

const InternalDevice = union(wlr.InputDevice.Type) {
    keyboard: hwc.input.Keyboard,
    pointer,
    touch,
    tablet,
    tablet_pad,
    @"switch",

    fn init(self: *InternalDevice, wlr_input_device: *wlr.InputDevice) !void {
        switch (wlr_input_device.type) {
            .keyboard => {
                self.* = .{ .keyboard = undefined };
                try self.keyboard.init(wlr_input_device.toKeyboard());
            },
            .pointer, .touch => {
                self.* = if (wlr_input_device.type == .pointer) .pointer else .touch;

                const seat = server.input_manager.default_seat;
                seat.cursor.wlr_cursor.attachInputDevice(wlr_input_device);
            },
            .tablet, .tablet_pad, .@"switch" => {},
        }
    }

    fn deinit(self: InternalDevice, wlr_input_device: *wlr.InputDevice) void {
        switch (self) {
            .keyboard => |*keyboard| @constCast(keyboard).deinit(),
            .pointer, .touch => {
                const seat = server.input_manager.default_seat;
                seat.cursor.wlr_cursor.detachInputDevice(wlr_input_device);
            },
            .tablet, .tablet_pad, .@"switch" => {},
        }
    }
};

link: wl.list.Link,
wlr_input_device: *wlr.InputDevice,
identifier: []const u8,
internal_device: InternalDevice,

destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(handleDestroy),

pub fn create(allocator: mem.Allocator, wlr_input_device: *wlr.InputDevice) !*hwc.input.Device {
    const device = try allocator.create(hwc.input.Device);
    errdefer allocator.destroy(device);

    const identifier = try createIdentifier(allocator, wlr_input_device);
    errdefer allocator.free(identifier);

    device.* = .{
        .link = undefined,
        .wlr_input_device = wlr_input_device,
        .identifier = identifier,
        .internal_device = undefined,
    };

    try device.internal_device.init(wlr_input_device);

    wlr_input_device.events.destroy.add(&device.destroy);

    log.info("{s}: identifier='{s}'", .{ @src().fn_name, device.identifier });

    return device;
}

fn createIdentifier(allocator: mem.Allocator, wlr_input_device: *wlr.InputDevice) ![]const u8 {
    var vendor: c_uint = 0;
    var product: c_uint = 0;

    if (@as(
        ?*libinput.Device,
        @alignCast(@ptrCast(wlr_input_device.getLibinputDevice())),
    )) |libinput_device| {
        vendor = libinput_device.getVendorId();
        product = libinput_device.getProductId();
    }

    const id = try fmt.allocPrint(allocator, "{s}-{}-{}-{s}", .{
        @tagName(wlr_input_device.type),
        vendor,
        product,
        mem.trim(u8, mem.sliceTo(wlr_input_device.name orelse "unkown", 0), &ascii.whitespace),
    });

    for (id) |*byte| {
        if (!ascii.isPrint(byte.*) or ascii.isWhitespace(byte.*)) {
            byte.* = '_';
        }
    }

    return id;
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.InputDevice),
    wlr_input_device: *wlr.InputDevice,
) void {
    const device: *hwc.input.Device = @fieldParentPtr("destroy", listener);

    device.destroy.link.remove();

    device.internal_device.deinit(wlr_input_device);

    log.info("{s}: identifier='{s}'", .{ @src().fn_name, device.identifier });

    server.allocator.free(device.identifier);
    server.allocator.destroy(device);
}
