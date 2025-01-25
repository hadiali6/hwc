const std = @import("std");
const log = std.log.scoped(.@"input.Manager");
const mem = std.mem;
const fmt = std.fmt;
const ascii = std.ascii;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const libinput = @import("libinput");

const hwc = @import("root");
const server = &hwc.server;

// const Device = struct {
//     link: wl.list.Link,
//     wlr_input_device: *wlr.InputDevice,
//     identifier: []const u8,
//
//     destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(handleDestroy),
//
//     pub fn create(allocator: mem.Allocator, wlr_input_device: *wlr.InputDevice) !*Device {
//         const device = try allocator.create(Device);
//         errdefer allocator.destroy(device);
//
//         const identifier = try createIdentifier(allocator, wlr_input_device);
//         errdefer allocator.free(identifier);
//
//         device.* = .{
//             .link = undefined,
//             .wlr_input_device = wlr_input_device,
//             .identifier = identifier,
//         };
//
//         wlr_input_device.events.destroy.add(&device.destroy);
//
//         log.info("{s}: identifier='{s}'", .{ @src().fn_name, device.identifier });
//
//         return device;
//     }
//
//     fn createIdentifier(allocator: mem.Allocator, wlr_input_device: *wlr.InputDevice) ![]const u8 {
//         var vendor: c_uint = 0;
//         var product: c_uint = 0;
//
//         if (@as(
//             ?*libinput.Device,
//             @alignCast(@ptrCast(wlr_input_device.getLibinputDevice())),
//         )) |libinput_device| {
//             vendor = libinput_device.getVendorId();
//             product = libinput_device.getProductId();
//         }
//
//         const id = try fmt.allocPrint(allocator, "{s}-{}-{}-{s}", .{
//             @tagName(wlr_input_device.type),
//             vendor,
//             product,
//             mem.trim(u8, mem.sliceTo(wlr_input_device.name orelse "unkown", 0), &ascii.whitespace),
//         });
//
//         for (id) |*byte| {
//             if (!ascii.isPrint(byte.*) or ascii.isWhitespace(byte.*)) {
//                 byte.* = '_';
//             }
//         }
//
//         return id;
//     }
//
//     fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
//         const device: *Device = @fieldParentPtr("destroy", listener);
//
//         log.info("{s}: identifier='{s}'", .{ @src().fn_name, device.identifier });
//
//         server.allocator.free(device.identifier);
//         server.allocator.destroy(device);
//     }
// };

default_seat: hwc.input.Seat,

devices: wl.list.Head(hwc.input.Device, .link),

new_input: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(handleNewInput),

pub fn init(self: *hwc.input.Manager) !void {
    self.* = .{
        .default_seat = undefined,
        .devices = undefined,
    };

    try self.default_seat.init("default");
    self.devices.init();

    server.wlr_backend.events.new_input.add(&self.new_input);
}

pub fn deinit(self: *hwc.input.Manager) void {
    self.new_input.link.remove();
}

fn handleNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    wlr_input_device: *wlr.InputDevice,
) void {
    const input_manager: *hwc.input.Manager = @fieldParentPtr("new_input", listener);

    const device = hwc.input.Device.create(server.allocator, wlr_input_device) catch |err| {
        log.err(
            "{s} failed: '{}': name='{s}'",
            .{ @src().fn_name, err, wlr_input_device.name orelse "unkown" },
        );
        return;
    };

    input_manager.devices.prepend(device);
    input_manager.default_seat.updateCapabilities();
}
