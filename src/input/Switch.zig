const std = @import("std");
const log = std.log.scoped(.input_switch);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const Type = enum {
    lid,
    tablet,
};

const State = union(Type) {
    lid: enum {
        open,
        close,
    },
    tablet: enum {
        off,
        on,
    },
};

device: hwc.input.Device,

toggle: wl.Listener(*wlr.Switch.event.Toggle) =
    wl.Listener(*wlr.Switch.event.Toggle).init(handleToggle),

pub fn init(self: *hwc.input.Switch, wlr_input_device: *wlr.InputDevice) !void {
    self.* = .{
        .device = undefined,
    };

    try self.device.init(wlr_input_device);
    errdefer self.device.deinit();

    wlr_input_device.toSwitch().events.toggle.add(&self.toggle);
}

pub fn deinit(self: *hwc.input.Switch) void {
    self.toggle.link.remove();

    self.device.deinit();
    util.allocator.destroy(self);
}

// This currently does nothing...
// TODO: apply switch bindings
fn handleToggle(_: *wl.Listener(*wlr.Switch.event.Toggle), event: *wlr.Switch.event.Toggle) void {
    var switch_type: Type = undefined;
    var switch_state: State = undefined;

    switch (event.switch_type) {
        .lid => {
            switch_type = .lid;
            switch_state = switch (event.switch_state) {
                .off => .{ .lid = .open },
                .on => .{ .lid = .close },
            };
        },
        .tablet_mode => {
            switch_type = .tablet;
            switch_state = switch (event.switch_state) {
                .off => .{ .tablet = .off },
                .on => .{ .tablet = .on },
            };
        },
    }
}
