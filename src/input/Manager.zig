const std = @import("std");
const log = std.log.scoped(.@"input.Manager");

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

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

    hwc.input.Device.create(server.allocator, wlr_input_device) catch |err| {
        log.err(
            "{s} failed: '{}': name='{s}'",
            .{ @src().fn_name, err, wlr_input_device.name orelse "unkown" },
        );
        return;
    };

    input_manager.default_seat.updateCapabilities();
}
