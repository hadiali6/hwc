pub const Config = @import("Config.zig");
pub const Output = @import("Output.zig");
pub const OutputManager = @import("OutputManager.zig");
pub const Server = @import("Server.zig");
pub const XdgDecoration = @import("Decoration.zig");
pub const XdgPopup = @import("XdgPopup.zig");
pub const XdgToplevel = @import("XdgToplevel.zig");

pub const input = struct {
    pub const Cursor = @import("input/Cursor.zig");
    pub const Device = @import("input/Device.zig");
    pub const Keybind = @import("input/Keybind.zig");
    pub const Keyboard = @import("input/Keyboard.zig");
    pub const KeyboardShortcutsInhibitor = @import("input/KeyboardShortcutsInhibitor.zig");
    pub const Manager = @import("input/Manager.zig");
    pub const PointerConstraint = @import("input/PointerConstraint.zig");
    pub const Relay = @import("input/Relay.zig");
    pub const Seat = @import("input/Seat.zig");
    pub const Switch = @import("input/Switch.zig");
    pub const Tablet = @import("input/Tablet.zig");
};
