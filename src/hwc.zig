const std = @import("std");
const fmt = std.fmt;

const wlr = @import("wlroots");

pub var server: Server = undefined;

pub const Server = @import("Server.zig");
pub const StatusManager = @import("StatusManager.zig");

pub const desktop = struct {
    pub const Focusable = union(enum) {
        toplevel: *XdgToplevel,
        layer_surface: *LayerSurface,
        none,

        pub fn wlrSurface(self: Focusable) ?*wlr.Surface {
            return switch (self) {
                .toplevel => |toplevel| toplevel.wlr_xdg_toplevel.base.surface,
                .layer_surface => |layer_surface| layer_surface.wlr_layer_surface.surface,
                .none => null,
            };
        }

        /// For logging purposes
        pub fn status(self: Focusable, buffer: []u8) ![]const u8 {
            return switch (self) {
                .toplevel => |toplevel| fmt.bufPrint(buffer, " [app_id='{?s}' title='{?s}']", .{
                    toplevel.wlr_xdg_toplevel.app_id,
                    toplevel.wlr_xdg_toplevel.title,
                }),
                .layer_surface => |layer_surface| fmt.bufPrint(buffer, " [namespace='{s}']", .{
                    layer_surface.wlr_layer_surface.namespace,
                }),
                .none => "",
            };
        }
    };

    pub const LayerSurface = @import("desktop/LayerSurface.zig");
    pub const Output = @import("desktop/Output.zig");
    pub const OutputManager = @import("desktop/OutputManager.zig");
    pub const SceneDescriptor = @import("desktop/SceneDescriptor.zig");
    pub const SurfaceManager = @import("desktop/SurfaceManager.zig");
    pub const XdgPopup = @import("desktop/XdgPopup.zig");
    pub const XdgToplevel = @import("desktop/XdgToplevel.zig");
};

pub const input = struct {
    pub const Cursor = @import("input/Cursor.zig");
    pub const Device = @import("input/Device.zig");
    pub const Keyboard = @import("input/Keyboard.zig");
    pub const Manager = @import("input/Manager.zig");
    pub const Seat = @import("input/Seat.zig");

    pub const util = @import("input/util.zig");
};
