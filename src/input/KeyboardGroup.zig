const std = @import("std");
const log = std.log.scoped(.input_keyboard_group);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

wlr_keyboard_group: *wlr.KeyboardGroup,
keyboard_identifiers: std.ArrayListUnmanaged([]const u8) = .{},
identifier: []const u8,

link: wl.list.Link,

pub fn init(self: *hwc.input.KeyboardGroup, seat: *hwc.input.Seat, id: []const u8) !void {
    const owned_id = try util.allocator.dupe(u8, id);
    errdefer util.allocator.free(owned_id);

    self.* = .{
        .wlr_keyboard_group = try wlr.KeyboardGroup.create(),
        .identifier = owned_id,
        .link = undefined,
    };
    errdefer self.wlr_keyboard_group.destroy();

    self.wlr_keyboard_group.data = @intFromPtr(self);

    seat.keyboard_groups.append(self);
    try server.input_manager.addDevice(&self.wlr_keyboard_group.keyboard.base);
}

pub fn deinit(self: *hwc.input.KeyboardGroup) void {
    util.allocator.free(self.identifier);

    for (self.keyboard_identifiers.items) |id| {
        util.allocator.free(id);
    }
    self.keyboard_identifiers.clearAndFree(util.allocator);

    _ = server.wl_server.getEventLoop().addIdle(*wlr.KeyboardGroup, struct {
        fn cb(wlr_keyboard_group: *wlr.KeyboardGroup) void {
            wlr_keyboard_group.destroy();
        }
    }.cb, self.wlr_keyboard_group) catch {
        self.wlr_keyboard_group.destroy();
    };

    self.link.remove();
    util.allocator.destroy(self);
}

pub fn addKeyboard(self: *hwc.input.KeyboardGroup, keyboard_device_id: []const u8) !void {
    var iterator = server.input_manager.devices.iterator(.forward);
    while (iterator.next()) |input_device| {
        const wlr_input_device = input_device.wlr_input_device;

        if (wlr_input_device.type != .keyboard) {
            continue;
        }

        const owned_device_id = try util.allocator.dupe(u8, keyboard_device_id);
        errdefer util.allocator.free(owned_device_id);

        try self.keyboard_identifiers.append(util.allocator, owned_device_id);
        errdefer _ = self.keyboard_identifiers.pop();

        if (std.mem.eql(u8, input_device.identifier, keyboard_device_id)) {
            const wlr_keyboard = wlr_input_device.toKeyboard();
            const success = self.wlr_keyboard_group.addKeyboard(wlr_keyboard);

            if (!success) {
                continue;
            }
        }
    }
}

pub fn removeKeyboard(self: *hwc.input.KeyboardGroup, keyboard_device_id: []const u8) void {
    for (self.keyboard_identifiers.items, 0..) |id, index| {
        if (std.mem.eql(u8, id, keyboard_device_id)) {
            util.allocator.free(self.keyboard_identifiers.orderedRemove(index));
            break;
        }
    } else {
        return;
    }

    var iterator = server.input_manager.devices.iterator(.forward);
    while (iterator.next()) |input_device| {
        const wlr_input_device = input_device.wlr_input_device;

        if (wlr_input_device.type != .keyboard) {
            continue;
        }

        if (std.mem.eql(u8, keyboard_device_id, input_device.identifier)) {
            const wlr_keyboard = wlr_input_device.toKeyboard();

            // FIXME: TODO: https://gitlab.freedesktop.org/wlroots/wlroots/-/issues/3934
            self.wlr_keyboard_group.removeKeyboard(wlr_keyboard);
        }
    }
}
