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

link: wl.list.Link,
wlr_input_device: *wlr.InputDevice,
identifier: []const u8,

destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(handleDestroy),

pub fn create(allocator: mem.Allocator, wlr_input_device: *wlr.InputDevice) !void {
    const device = try allocator.create(hwc.input.Device);
    errdefer allocator.destroy(device);

    const identifier = try createIdentifier(allocator, wlr_input_device);
    errdefer allocator.free(identifier);

    device.* = .{
        .link = undefined,
        .wlr_input_device = wlr_input_device,
        .identifier = identifier,
    };

    wlr_input_device.events.destroy.add(&device.destroy);

    server.input_manager.devices.prepend(device);

    log.info("{s}: '{s}'", .{ @src().fn_name, device.identifier });
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

fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const device: *hwc.input.Device = @fieldParentPtr("destroy", listener);

    device.destroy.link.remove();

    log.info("{s}: '{s}'", .{ @src().fn_name, device.identifier });

    server.allocator.free(device.identifier);
    server.allocator.destroy(device);
}
