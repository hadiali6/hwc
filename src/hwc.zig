const wlr = @import("wlroots");

pub const Config = @import("Config.zig");
pub const Output = @import("Output.zig");
pub const OutputManager = @import("OutputManager.zig");
pub const Server = @import("Server.zig");
pub const XdgDecoration = @import("Decoration.zig");
pub const XdgPopup = @import("XdgPopup.zig");
pub const XdgToplevel = @import("XdgToplevel.zig");

pub const Focusable = union(enum) {
    none: void,
    toplevel: *XdgToplevel,
    // TODO:
    // layersurface
    // locksurface
    // xwayland

    pub fn wlrSurface(self: Focusable) ?*wlr.Surface {
        return switch (self) {
            .toplevel => |toplevel| toplevel.xdg_toplevel.base.surface,
            .none => null,
        };
    }
};

pub const input = struct {
    pub const Cursor = @import("input/Cursor.zig");
    pub const Device = @import("input/Device.zig");
    pub const Keybind = @import("input/Keybind.zig");
    pub const Keyboard = @import("input/Keyboard.zig");
    pub const KeyboardGroup = @import("input/KeyboardGroup.zig");
    pub const KeyboardShortcutsInhibitor = @import("input/KeyboardShortcutsInhibitor.zig");
    pub const Manager = @import("input/Manager.zig");
    pub const PointerConstraint = @import("input/PointerConstraint.zig");
    pub const Relay = @import("input/Relay.zig");
    pub const Seat = @import("input/Seat.zig");
    pub const Switch = @import("input/Switch.zig");
    pub const Tablet = @import("input/Tablet.zig");
};
