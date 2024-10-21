const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.keybind);

const wlr = @import("wlroots");
const xkb = @import("xkbcommon");
const ziglua = @import("ziglua");

const hwc = @import("hwc.zig");
const lua_state = &@import("root").lua_state;

keysym: xkb.Keysym,
modifiers: wlr.Keyboard.ModifierMask,

/// Lua registry reference to callback function
lua_fn_reference: i32 = ziglua.ref_nil,

/// Unique identifier used to identify each Keybind instance
id: u32,

/// When set to true the mapping will be executed on key release rather than on press
exec_on_release: bool,

/// When set to true the mapping will be executed repeatedly while key is pressed
repeat: bool,

// This is set for mappings with layout-pinning
// If set, the layout with this index is always used to translate the given keycode
layout_index: ?u32,

pub fn match(
    keybind: hwc.Keybind,
    keycode: xkb.Keycode,
    modifiers: wlr.Keyboard.ModifierMask,
    released: bool,
    xkb_state: *xkb.State,
    method: enum { no_translate, translate },
) bool {
    if (released != keybind.exec_on_release) return false;

    const keymap = xkb_state.getKeymap();

    // If the mapping has no pinned layout, use the active layout.
    // It doesn't matter if the index is out of range, since xkbcommon
    // will fall back to the active layout if so.
    const layout_index = keybind.layout_index orelse xkb_state.keyGetLayout(keycode);

    switch (method) {
        .no_translate => {
            // Get keysyms from the base layer, as if modifiers didn't change keysyms.
            // E.g. pressing `Super+Shift 1` does not translate to `Super Exclam`.
            const keysyms = keymap.keyGetSymsByLevel(
                keycode,
                layout_index,
                0,
            );

            if (@as(u32, @bitCast(modifiers)) == @as(u32, @bitCast(keybind.modifiers))) {
                for (keysyms) |sym| {
                    if (sym == keybind.keysym) {
                        return true;
                    }
                }
            }
        },
        .translate => {
            // Keysyms and modifiers as translated by xkb.
            // Modifiers used to translate the key are consumed.
            // E.g. pressing `Super+Shift 1` translates to `Super Exclam`.
            const keysyms_translated = keymap.keyGetSymsByLevel(
                keycode,
                layout_index,
                xkb_state.keyGetLevel(keycode, layout_index),
            );

            const consumed = xkb_state.keyGetConsumedMods2(keycode, .xkb);
            const modifiers_translated = @as(u32, @bitCast(modifiers)) & ~consumed;

            if (modifiers_translated == @as(u32, @bitCast(keybind.modifiers))) {
                for (keysyms_translated) |sym| {
                    if (sym == keybind.keysym) {
                        return true;
                    }
                }
            }
        },
    }

    return false;
}

pub fn parseKeysym(keysym_str: [:0]const u8) !xkb.Keysym {
    const keysym = xkb.Keysym.fromName(keysym_str, .case_insensitive);
    if (keysym == .NoSymbol) {
        log.err("invalid keysym '{s}'", .{keysym_str});
        return error.Other;
    }

    // The case insensitive matching done by xkbcommon returns the first
    // lowercase match found if there are multiple matches that differ only in
    // case. This works great for alphabetic keys for example but there is one
    // problematic exception we handle specially here. For some reason there
    // exist both uppercase and lowercase versions of XF86ScreenSaver with
    // different keysym values for example. Switching to a case-sensitive match
    // would be too much of a breaking change at this point so fix this by
    // special-casing this exception.
    //
    // This has been fixed upstream in libxkbcommon 1.7.0
    // https://github.com/xkbcommon/libxkbcommon/pull/465
    // TODO remove the workaround once libxkbcommon 1.7.0 is widely distributed.
    if (@intFromEnum(keysym) == xkb.Keysym.XF86Screensaver) {
        if (mem.eql(u8, keysym_str, "XF86Screensaver")) {
            return keysym;
        } else if (mem.eql(u8, keysym_str, "XF86ScreenSaver")) {
            return @enumFromInt(xkb.Keysym.XF86ScreenSaver);
        } else {
            log.err("ambiguous keysym name '{s}'", .{keysym_str});
            return error.Other;
        }
    }

    return keysym;
}

pub fn parseModifiers(modifiers_str: []const u8) !wlr.Keyboard.ModifierMask {
    var it = mem.split(u8, modifiers_str, "+");
    var modifiers = wlr.Keyboard.ModifierMask{};
    outer: while (it.next()) |mod_name| {
        if (mem.eql(u8, mod_name, "None")) continue;
        inline for ([_]struct { name: []const u8, field_name: []const u8 }{
            .{ .name = "Shift", .field_name = "shift" },
            .{ .name = "Control", .field_name = "ctrl" },
            .{ .name = "Mod1", .field_name = "alt" },
            .{ .name = "Alt", .field_name = "alt" },
            .{ .name = "Mod3", .field_name = "mod3" },
            .{ .name = "Mod4", .field_name = "logo" },
            .{ .name = "Super", .field_name = "logo" },
            .{ .name = "Mod5", .field_name = "mod5" },
        }) |def| {
            if (mem.eql(u8, def.name, mod_name)) {
                @field(modifiers, def.field_name) = true;
                continue :outer;
            }
        }
        log.err("invalid modifier '{s}'", .{mod_name});
        return error.Other;
    }
    return modifiers;
}

pub fn runLuaCallback(self: *const hwc.Keybind) !void {
    if (self.lua_fn_reference == ziglua.ref_nil) {
        log.err("No Lua function stored", .{});
        return error.NoLuaFunctionStored;
    }
    _ = lua_state.*.rawGetIndex(ziglua.registry_index, self.lua_fn_reference);
    try lua_state.*.protectedCall(0, 0, 0);
}
