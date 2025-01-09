const std = @import("std");
const log = std.log.scoped(.input_keyboard_shortcuts_inhibitor);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

wlr_keyboard_shortcuts_inhibitor: *wlr.KeyboardShortcutsInhibitorV1,

destroy: wl.Listener(*wlr.KeyboardShortcutsInhibitorV1) =
    wl.Listener(*wlr.KeyboardShortcutsInhibitorV1).init(handleDestroy),

pub fn create(wlr_keyboard_shortcuts_inhibitor: *wlr.KeyboardShortcutsInhibitorV1) !void {
    const inhibitor = try util.allocator.create(hwc.input.KeyboardShortcutsInhibitor);
    errdefer util.allocator.destroy(inhibitor);

    inhibitor.* = .{
        .wlr_keyboard_shortcuts_inhibitor = wlr_keyboard_shortcuts_inhibitor,
    };

    wlr_keyboard_shortcuts_inhibitor.data = @intFromPtr(inhibitor);

    inhibitor.wlr_keyboard_shortcuts_inhibitor.events.destroy.add(&inhibitor.destroy);
}

pub fn deinit(self: *hwc.input.KeyboardShortcutsInhibitor) void {
    self.destroy.link.remove();
    util.allocator.destroy(self);
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.KeyboardShortcutsInhibitorV1),
    _: *wlr.KeyboardShortcutsInhibitorV1,
) void {
    const inhibitor: *hwc.input.KeyboardShortcutsInhibitor = @fieldParentPtr("destroy", listener);

    if (hwc.Focusable.fromSurface(inhibitor.wlr_keyboard_shortcuts_inhibitor.surface)) |focusable| {
        if (focusable.* == .toplevel) {
            focusable.toplevel.keyboard_shortcuts_inhibit = false;
        }
    }

    inhibitor.deinit();
}
