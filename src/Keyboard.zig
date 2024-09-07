const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const server = &@import("main.zig").server;

const log = std.log.scoped(.keyboard);
const gpa = std.heap.c_allocator;

pub const Keyboard = struct {
    link: wl.list.Link = undefined,
    device: *wlr.InputDevice,

    modifiers: wl.Listener(*wlr.Keyboard) =
        wl.Listener(*wlr.Keyboard).init(modifiers),
    key: wl.Listener(*wlr.Keyboard.event.Key) =
        wl.Listener(*wlr.Keyboard.event.Key).init(key),

    pub fn create(device: *wlr.InputDevice) !void {
        const keyboard = try gpa.create(Keyboard);
        errdefer gpa.destroy(keyboard);

        keyboard.* = .{
            .device = device,
        };

        const context = xkb.Context.new(.no_flags) orelse return error.ContextFailed;
        defer context.unref();
        const keymap = xkb.Keymap.newFromNames(context, null, .no_flags) orelse return error.KeymapFailed;
        defer keymap.unref();

        const wlr_keyboard = device.toKeyboard();
        if (!wlr_keyboard.setKeymap(keymap)) return error.SetKeymapFailed;
        wlr_keyboard.setRepeatInfo(25, 600);

        wlr_keyboard.events.modifiers.add(&keyboard.modifiers);
        wlr_keyboard.events.key.add(&keyboard.key);

        server.seat.setKeyboard(wlr_keyboard);
        server.keyboards.append(keyboard);
    }

    fn modifiers(
        _: *wl.Listener(*wlr.Keyboard),
        wlr_keyboard: *wlr.Keyboard,
    ) void {
        // const keyboard: *Keyboard = @fieldParentPtr("modifiers", listener);
        server.seat.setKeyboard(wlr_keyboard);
        server.seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
    }

    fn key(
        listener: *wl.Listener(*wlr.Keyboard.event.Key),
        event: *wlr.Keyboard.event.Key,
    ) void {
        const keyboard: *Keyboard = @fieldParentPtr("key", listener);
        const wlr_keyboard = keyboard.device.toKeyboard();

        // Translate libinput keycode -> xkbcommon
        const keycode = event.keycode + 8;

        // If the keyboard is in a group, this event will be handled by the group's Keyboard instance.
        if (wlr_keyboard.group != null) return;

        var handled = false;
        if (wlr_keyboard.getModifiers().alt and event.state == .pressed) {
            for (wlr_keyboard.xkb_state.?.keyGetSyms(keycode)) |sym| {
                if (server.handleKeybind(sym)) {
                    handled = true;
                    break;
                }
            }
        }

        if (!handled) {
            server.seat.setKeyboard(wlr_keyboard);
            server.seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
        }
    }
};
