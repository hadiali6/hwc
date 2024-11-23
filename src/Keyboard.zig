const std = @import("std");
const log = std.log.scoped(.keyboard);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const ziglua = @import("ziglua");

const util = @import("util.zig");
const hwc = @import("hwc.zig");
const lua = @import("lua.zig");

const server = &@import("root").server;

link: wl.list.Link = undefined,
device: *wlr.InputDevice,

modifiers: wl.Listener(*wlr.Keyboard) =
    wl.Listener(*wlr.Keyboard).init(handleModifiers),
key: wl.Listener(*wlr.Keyboard.event.Key) =
    wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),

pub fn create(device: *wlr.InputDevice) !void {
    const keyboard = try util.allocator.create(hwc.Keyboard);
    errdefer util.allocator.destroy(keyboard);

    keyboard.* = .{
        .device = device,
    };

    const context = xkb.Context.new(.no_flags) orelse return error.ContextFailed;
    defer context.unref();
    const keymap = xkb.Keymap.newFromNames(context, null, .no_flags) orelse return error.KeymapFailed;
    defer keymap.unref();

    const wlr_keyboard = device.toKeyboard();
    if (!wlr_keyboard.setKeymap(keymap)) return error.SetKeymapFailed;
    wlr_keyboard.setRepeatInfo(
        server.config.keyboard_repeat_rate,
        server.config.keyboard_repeat_delay,
    );

    wlr_keyboard.events.modifiers.add(&keyboard.modifiers);
    wlr_keyboard.events.key.add(&keyboard.key);

    server.input_manager.seat.wlr_seat.setKeyboard(wlr_keyboard);
    server.input_manager.all_keyboards.append(keyboard);
}

fn handleModifiers(
    _: *wl.Listener(*wlr.Keyboard),
    wlr_keyboard: *wlr.Keyboard,
) void {
    const wlr_seat = server.input_manager.seat.wlr_seat;
    wlr_seat.setKeyboard(wlr_keyboard);
    wlr_seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn handleKey(
    listener: *wl.Listener(*wlr.Keyboard.event.Key),
    event: *wlr.Keyboard.event.Key,
) void {
    const keyboard: *hwc.Keyboard = @fieldParentPtr("key", listener);
    const wlr_keyboard = keyboard.device.toKeyboard();
    var seat = &server.input_manager.seat;

    // If the keyboard is in a group, this event will be handled by the group's Keyboard instance.
    if (wlr_keyboard.group != null) return;

    seat.clearRepeatingMapping();

    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;

    const modifiers = wlr_keyboard.getModifiers();

    // We must ref() the state here as a mapping could change the keyboard layout.
    const xkb_state = (wlr_keyboard.xkb_state orelse return).ref();
    defer xkb_state.unref();

    const keysyms = xkb_state.keyGetSyms(keycode);

    for (keysyms) |sym| {
        if (!(event.state == .released) and ttyKeybinds(sym)) {
            return;
        }
    }

    const keybind_was_run = if (event.state == .pressed) seat.handleKeybind(
        keycode,
        modifiers,
        event.state == .released,
        xkb_state,
    ) else false;

    if (!keybind_was_run) {
        seat.wlr_seat.setKeyboard(wlr_keyboard);
        seat.wlr_seat.keyboardNotifyKey(
            event.time_msec,
            event.keycode,
            event.state,
        );
    }

    if (event.state == .released) _ = seat.handleKeybind(
        keycode,
        modifiers,
        event.state == .released,
        xkb_state,
    );
}

/// Handle hardcoded VT switching keybinds.
/// Returns true if the keysym was handled.
fn ttyKeybinds(keysym: xkb.Keysym) bool {
    switch (@intFromEnum(keysym)) {
        xkb.Keysym.XF86Switch_VT_1...xkb.Keysym.XF86Switch_VT_12 => {
            log.debug("switch VT keysym received", .{});
            if (server.session) |session| {
                const vt = @intFromEnum(keysym) - xkb.Keysym.XF86Switch_VT_1 + 1;
                const log_server = std.log.scoped(.server);
                log_server.info("switching to VT {}", .{vt});
                session.changeVt(vt) catch log_server.err("changing VT failed", .{});
            }
        },
        else => return false,
    }
    return true;
}
