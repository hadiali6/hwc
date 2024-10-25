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

    server.seat.setKeyboard(wlr_keyboard);
    server.keyboards.append(keyboard);
}

fn handleModifiers(
    _: *wl.Listener(*wlr.Keyboard),
    wlr_keyboard: *wlr.Keyboard,
) void {
    server.seat.setKeyboard(wlr_keyboard);
    server.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn handleKey(
    listener: *wl.Listener(*wlr.Keyboard.event.Key),
    event: *wlr.Keyboard.event.Key,
) void {
    const keyboard: *hwc.Keyboard = @fieldParentPtr("key", listener);
    const wlr_keyboard = keyboard.device.toKeyboard();

    // If the keyboard is in a group, this event will be handled by the group's Keyboard instance.
    if (wlr_keyboard.group != null) return;

    server.clearRepeatingMapping();

    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;

    const modifiers = wlr_keyboard.getModifiers();

    // We must ref() the state here as a mapping could change the keyboard layout.
    const xkb_state = (wlr_keyboard.xkb_state orelse return).ref();
    defer xkb_state.unref();

    const keysyms = xkb_state.keyGetSyms(keycode);

    for (keysyms) |sym| {
        if (!(event.state == .released) and ttyKeybinds(sym)) return;
    }

    const keybind_was_run = if (event.state == .pressed) handleKeybind(
        keycode,
        modifiers,
        event.state == .released,
        xkb_state,
    ) else false;

    if (!keybind_was_run) {
        server.seat.setKeyboard(wlr_keyboard);
        server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }

    if (event.state == .released) _ = handleKeybind(
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

/// Handle any user-defined mapping for passed keycode, modifiers and keyboard state
/// Returns true if a mapping was run
pub fn handleKeybind(
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
    var found: ?*hwc.Keybind = null;

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
            server.repeating_keybind = keybind;
            server.keybind_repeat_timer.timerUpdate(server.config.keyboard_repeat_delay) catch {
                log.err("failed to update mapping repeat timer", .{});
            };
        }
        keybind.runLuaCallback() catch return false;
        return true;
    }

    return false;
}
