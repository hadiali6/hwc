const std = @import("std");
const log = std.log.scoped(.@"input.Keyboard");
const assert = std.debug.assert;
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const hwc = @import("root");
const server = &hwc.server;

wlr_keyboard: *wlr.Keyboard,

key: wl.Listener(*wlr.Keyboard.event.Key) = wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),
modifiers: wl.Listener(*wlr.Keyboard) = wl.Listener(*wlr.Keyboard).init(handleModifiers),

pub fn init(self: *hwc.input.Keyboard, wlr_keyboard: *wlr.Keyboard) !void {
    self.* = .{
        .wlr_keyboard = wlr_keyboard,
    };

    wlr_keyboard.events.key.add(&self.key);
    wlr_keyboard.events.modifiers.add(&self.modifiers);

    {
        const xkb_context = xkb.Context.new(.no_flags) orelse return error.XkbContextFailed;
        defer xkb_context.unref();

        const xkb_keymap = xkb.Keymap.newFromNames(xkb_context, null, .no_flags) orelse
            return error.XkbKeymapFailed;
        defer xkb_keymap.unref();

        if (!wlr_keyboard.setKeymap(xkb_keymap)) {
            return error.XkbSetKeymapFailed;
        }
    }

    wlr_keyboard.setRepeatInfo(50, 300);

    {
        var seat = server.input_manager.default_seat;

        seat.wlr_seat.setKeyboard(wlr_keyboard);
        assert(seat.wlr_seat.getKeyboard() != null);

        if (seat.wlr_seat.keyboard_state.focused_surface) |focused_wlr_surface| {
            seat.keyboardNotifyEnter(focused_wlr_surface);
        }
    }

    log.info("{s}", .{@src().fn_name});
}

pub fn deinit(self: *hwc.input.Keyboard) void {
    self.key.link.remove();
    self.modifiers.link.remove();

    log.info("{s}", .{@src().fn_name});
}

fn handleModifiers(_: *wl.Listener(*wlr.Keyboard), wlr_keyboard: *wlr.Keyboard) void {
    // if the keyboard is in a group, this event will be handled by the group's Keyboard instance
    if (wlr_keyboard.group != null) {
        return;
    }

    const wlr_seat = server.input_manager.default_seat.wlr_seat;
    wlr_seat.setKeyboard(wlr_keyboard);
    wlr_seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);

    const mods = wlr_keyboard.getModifiers();
    log.debug(
        "{s}: shift='{}' caps='{}' ctrl='{}' alt='{}' mod2='{}' mod3='{}' logo='{}' mod5='{}'",
        .{ @src().fn_name, mods.shift, mods.caps, mods.ctrl, mods.alt, mods.mod2, mods.mod3, mods.logo, mods.mod5 },
    );
}

fn handleKey(
    listener: *wl.Listener(*wlr.Keyboard.event.Key),
    event: *wlr.Keyboard.event.Key,
) void {
    const keyboard: *hwc.input.Keyboard = @fieldParentPtr("key", listener);
    const wlr_keyboard = keyboard.wlr_keyboard;

    // if the keyboard is in a group, this event will be handled by the group's Keyboard instance
    if (wlr_keyboard.group != null) {
        return;
    }

    // translate libinput keycode -> xkbcommon
    const xkb_keycode = event.keycode + 8;

    const xkb_state = (wlr_keyboard.xkb_state orelse return).ref();
    defer xkb_state.unref();

    const keysyms = xkb_state.keyGetSyms(xkb_keycode);

    const keybind_executed = blk: {
        for (keysyms) |sym| {
            log.debug("{s} key='{s}'", .{ @src().fn_name, inner_blk: {
                var buffer: [64]u8 = undefined;
                _ = sym.getName(&buffer, buffer.len);
                break :inner_blk buffer;
            } });

            break :blk event.state == .pressed and vtKeybind(sym);
        } else break :blk false;
    };

    if (!keybind_executed) {
        const wlr_seat = server.input_manager.default_seat.wlr_seat;
        wlr_seat.setKeyboard(wlr_keyboard);
        wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
    }
}

fn vtKeybind(keysym: xkb.Keysym) bool {
    switch (@intFromEnum(keysym)) {
        xkb.Keysym.XF86Switch_VT_1...xkb.Keysym.XF86Switch_VT_12 => {
            log.debug("{s}: switch VT keysym received: {}", .{ @src().fn_name, keysym });

            if (server.wlr_session) |wlr_session| {
                const vt = @intFromEnum(keysym) - xkb.Keysym.XF86Switch_VT_1 + 1;

                log.info("{s}: switching to VT {}", .{ @src().fn_name, vt });
                wlr_session.changeVt(vt) catch |err| {
                    log.err("{s}: failed: '{}'", .{ @src().fn_name, err });
                };
            }

            return true;
        },
        else => return false,
    }
}
