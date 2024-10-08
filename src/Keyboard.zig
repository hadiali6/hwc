const std = @import("std");
const log = std.log.scoped(.keyboard);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const config = @import("config.zig");
const util = @import("util.zig");
const hwc = @import("hwc.zig");
const lua = @import("lua.zig");

const main = @import("root");
const server = &main.server;

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
    wlr_keyboard.setRepeatInfo(config.keyboard_rate, config.keyboard_delay);

    wlr_keyboard.events.modifiers.add(&keyboard.modifiers);
    wlr_keyboard.events.key.add(&keyboard.key);

    server.seat.setKeyboard(wlr_keyboard);
    server.keyboards.append(keyboard);
}

fn handleModifiers(
    _: *wl.Listener(*wlr.Keyboard),
    wlr_keyboard: *wlr.Keyboard,
) void {
    // const keyboard: *hwc.Keyboard = @fieldParentPtr("modifiers", listener);
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

    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;

    const xkb_state = (wlr_keyboard.xkb_state orelse return).ref();
    defer xkb_state.unref();
    const keysyms = xkb_state.keyGetSyms(keycode);

    var handled = false;
    const modifiers = wlr_keyboard.getModifiers();
    if (event.state == .pressed) {
        for (keysyms) |sym| {
            if (handleBuiltinMapping(modifiers, sym)) {
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

/// Handle any builtin, harcoded compsitor mappings such as VT switching.
/// Returns true if the keysym was handled.
fn handleBuiltinMapping(
    modifiers: wlr.Keyboard.ModifierMask,
    keysym: xkb.Keysym,
) bool {
    var result: bool = undefined;
    if (modifiers.alt and modifiers.ctrl) {
        result = ttyBinds(keysym);
    } else if (modifiers.alt) {
        result = normalBinds(keysym);
    }
    return result;
}

fn ttyBinds(keysym: xkb.Keysym) bool {
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

fn normalBinds(keysym: xkb.Keysym) bool {
    switch (@intFromEnum(keysym)) {
        // Exit the compositor
        xkb.Keysym.Escape => server.wl_server.terminate(),
        // Focus the next toplevel in the stack, pushing the current top to the back
        xkb.Keysym.F1 => {
            if (server.mapped_toplevels.length() < 2) return true;
            const toplevel: *hwc.XdgToplevel = @fieldParentPtr("link", server.mapped_toplevels.link.prev.?);
            server.focusToplevel(toplevel, toplevel.xdg_toplevel.base.surface);
        },
        // Set focused toplevel to fullscreen.
        xkb.Keysym.f => {
            const toplevel: *hwc.XdgToplevel = @fieldParentPtr("link", server.mapped_toplevels.link.prev.?);
            if (toplevel.scene_tree.node.enabled) {
                toplevel.xdg_toplevel.events.request_fullscreen.emit();
            }
        },
        // Set focused toplevel to maximized.
        xkb.Keysym.M => {
            const toplevel: *hwc.XdgToplevel = @fieldParentPtr("link", server.mapped_toplevels.link.prev.?);
            if (toplevel.scene_tree.node.enabled) {
                toplevel.xdg_toplevel.events.request_maximize.emit();
            }
        },
        // Set focused toplevel to minimized.
        xkb.Keysym.m => {
            const toplevel: *hwc.XdgToplevel = @fieldParentPtr("link", server.mapped_toplevels.link.prev.?);
            if (toplevel.scene_tree.node.enabled) {
                toplevel.xdg_toplevel.events.request_minimize.emit();
            }
        },
        // Rerun config script.
        xkb.Keysym.r => {
            lua.runScript(main.lua_state) catch {};
        },
        else => return false,
    }
    return true;
}
