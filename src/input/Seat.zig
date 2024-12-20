const std = @import("std");
const log = std.log.scoped(.seat);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const hwc = @import("../hwc.zig");
const util = @import("../util.zig");

const server = &@import("root").server;

wlr_seat: *wlr.Seat,
cursor: hwc.input.Cursor,
relay: hwc.input.Relay,

/// Timer for repeating keyboard mappings
keybind_repeat_timer: *wl.EventSource,

/// Currently repeating mapping, if any
repeating_keybind: ?*const hwc.input.Keybind = null,

request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) =
    wl.Listener(*wlr.Seat.event.RequestSetCursor).init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) =
    wl.Listener(*wlr.Seat.event.RequestSetSelection).init(handleRequestSetSelection),

pub fn init(self: *hwc.input.Seat) !void {
    const event_loop = server.wl_server.getEventLoop();
    const keybind_repeat_timer = try event_loop.addTimer(
        *hwc.input.Seat,
        handleMappingRepeatTimeout,
        self,
    );
    errdefer keybind_repeat_timer.remove();

    self.* = .{
        .keybind_repeat_timer = keybind_repeat_timer,
        .wlr_seat = try wlr.Seat.create(server.wl_server, "seat0"),
        .cursor = undefined,
        .relay = undefined,
    };

    self.wlr_seat.data = @intFromPtr(self);

    try self.cursor.init();
    self.relay.init();

    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
}

pub fn deinit(self: *hwc.input.Seat) void {
    self.keybind_repeat_timer.remove();
    self.cursor.deinit();
}

fn handleRequestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_cursor", listener);
    if (event.seat_client == seat.wlr_seat.pointer_state.focused_client) {
        seat.cursor.wlr_cursor.setSurface(
            event.surface,
            event.hotspot_x,
            event.hotspot_y,
        );
    }
}

fn handleRequestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    const seat: *hwc.input.Seat = @fieldParentPtr("request_set_selection", listener);
    seat.wlr_seat.setSelection(event.source, event.serial);
}

fn handleMappingRepeatTimeout(self: *hwc.input.Seat) c_int {
    if (self.repeating_keybind) |keybind| {
        const rate = server.config.keyboard_repeat_rate;
        const ms_delay = if (rate > 0) 1000 / rate else 0;
        self.keybind_repeat_timer.timerUpdate(ms_delay) catch {
            log.err("failed to update mapping repeat timer", .{});
        };
        keybind.runLuaCallback() catch {
            log.err("repeating keybind lua function failed", .{});
        };
    }
    return 0;
}

pub fn clearRepeatingMapping(self: *hwc.input.Seat) void {
    self.keybind_repeat_timer.timerUpdate(0) catch {
        log.err("failed to clear mapping repeat timer", .{});
    };
    self.repeating_keybind = null;
}

/// Handle any user-defined mapping for passed keycode, modifiers and keyboard state
/// Returns true if a mapping was run
pub fn handleKeybind(
    self: *hwc.input.Seat,
    keycode: xkb.Keycode,
    modifiers: wlr.Keyboard.ModifierMask,
    released: bool,
    xkb_state: *xkb.State,
) bool {
    // It is possible for more than one mapping to be matched due to the
    // existence of layout-independent mappings. It is also possible due to
    // translation by xkbcommon consuming modifiers. On the swedish layout
    // for example, translating Super+Shift+Space may consume the Shift
    // modifier and confict with a mapping for Super+Space. For this reason,
    // matching wihout xkbcommon translation is done first and after a match
    // has been found all further matches are ignored.
    var found: ?*hwc.input.Keybind = null;

    // First check for matches without translating keysyms with xkbcommon.
    // That is, if the physical keys Mod+Shift+1 are pressed on a US layout don't
    // translate the keysym 1 to an exclamation mark. This behavior is generally
    // what is desired.
    for (server.config.keybinds.items) |*keybind| {
        if (keybind.match(keycode, modifiers, released, xkb_state, .no_translate)) {
            if (found == null) {
                found = keybind;
            } else {
                log.debug("already found a matching mapping, ignoring additional match", .{});
            }
        }
    }

    // There are however some cases where it is necessary to translate keysyms
    // with xkbcommon for intuitive behavior. For example, layouts may require
    // translation with the numlock modifier to obtain keypad number keysyms
    // (e.g. KP_1).
    for (server.config.keybinds.items) |*keybind| {
        if (keybind.match(keycode, modifiers, released, xkb_state, .translate)) {
            if (found == null) {
                found = keybind;
            } else {
                log.debug("already found a matching mapping, ignoring additional match", .{});
            }
        }
    }

    // The mapped command must be run outside of the loop above as it may modify
    // the list of mappings we are iterating through, possibly causing it to be re-allocated.
    if (found) |keybind| {
        if (keybind.repeat) {
            self.repeating_keybind = keybind;
            self.keybind_repeat_timer.timerUpdate(server.config.keyboard_repeat_delay) catch {
                log.err("failed to update mapping repeat timer", .{});
            };
        }
        keybind.runLuaCallback() catch return false;
        return true;
    }

    return false;
}

pub fn updateCapabilities(self: *hwc.input.Seat) void {
    var capabilities = wl.Seat.Capability{};

    var iterator = server.input_manager.devices.iterator(.forward);
    while (iterator.next()) |device| {
        switch (device.wlr_input_device.type) {
            .keyboard => capabilities.keyboard = true,
            .pointer => capabilities.pointer = true,
            .touch => capabilities.touch = true,
            .tablet => {},
            .@"switch", .tablet_pad => unreachable,
        }
    }

    self.wlr_seat.setCapabilities(capabilities);
}

pub fn keyboardNotifyEnter(self: *hwc.input.Seat, wlr_surface: *wlr.Surface) void {
    if (self.wlr_seat.getKeyboard()) |wlr_keyboard| {
        self.wlr_seat.keyboardNotifyEnter(
            wlr_surface,
            wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
            &wlr_keyboard.modifiers,
        );
    } else {
        self.wlr_seat.keyboardNotifyEnter(wlr_surface, &.{}, null);
    }
}
