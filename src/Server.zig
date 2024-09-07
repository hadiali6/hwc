const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const Toplevel = @import("XdgToplevel.zig").Toplevel;
const Keyboard = @import("Keyboard.zig").Keyboard;
const Output = @import("Output.zig").Output;
const Cursor = @import("Cursor.zig").Cursor;

const log = std.log.scoped(.server);

pub const Server = struct {
    wl_server: *wl.Server,
    backend: *wlr.Backend,
    renderer: *wlr.Renderer,
    allocator: *wlr.Allocator,
    scene: *wlr.Scene,

    output_layout: *wlr.OutputLayout,
    scene_output_layout: *wlr.SceneOutputLayout,
    new_output: wl.Listener(*wlr.Output) =
        wl.Listener(*wlr.Output).init(newOutput),

    xdg_shell: *wlr.XdgShell,
    new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) =
        wl.Listener(*wlr.XdgToplevel).init(newXdgToplevel),
    mapped_toplevels: wl.list.Head(Toplevel, .link) = undefined,

    seat: *wlr.Seat,
    new_input: wl.Listener(*wlr.InputDevice) =
        wl.Listener(*wlr.InputDevice).init(newInput),
    request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) =
        wl.Listener(*wlr.Seat.event.RequestSetCursor).init(requestSetCursor),
    request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) =
        wl.Listener(*wlr.Seat.event.RequestSetSelection).init(requestSetSelection),
    keyboards: wl.list.Head(Keyboard, .link) = undefined,

    cursor: Cursor,

    pub fn init(self: *Server) !void {
        const wl_server = try wl.Server.create();
        const loop = wl_server.getEventLoop();
        const backend = try wlr.Backend.autocreate(loop, null);
        const renderer = try wlr.Renderer.autocreate(backend);
        const output_layout = try wlr.OutputLayout.create(wl_server);
        const scene = try wlr.Scene.create();
        self.* = .{
            .wl_server = wl_server,
            .backend = backend,
            .renderer = renderer,
            .allocator = try wlr.Allocator.autocreate(backend, renderer),
            .scene = scene,
            .output_layout = output_layout,
            .scene_output_layout = try scene.attachOutputLayout(output_layout),
            .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
            .seat = try wlr.Seat.create(wl_server, "default"),
            .cursor = undefined,
        };
        try self.cursor.init();

        try self.renderer.initServer(wl_server);

        _ = try wlr.Compositor.create(self.wl_server, 6, self.renderer);
        _ = try wlr.Subcompositor.create(self.wl_server);
        _ = try wlr.DataDeviceManager.create(self.wl_server);

        self.backend.events.new_output.add(&self.new_output);

        self.xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);
        self.mapped_toplevels.init();

        self.backend.events.new_input.add(&self.new_input);
        self.seat.events.request_set_cursor.add(&self.request_set_cursor);
        self.seat.events.request_set_selection.add(&self.request_set_selection);
        self.keyboards.init();
    }

    pub fn deinit(self: *Server) void {
        self.cursor.deinit();
        self.wl_server.destroyClients();
        self.wl_server.destroy();
    }

    fn newOutput(
        listener: *wl.Listener(*wlr.Output),
        wlr_output: *wlr.Output,
    ) void {
        const server: *Server = @fieldParentPtr("new_output", listener);

        if (!wlr_output.initRender(server.allocator, server.renderer)) return;

        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(true);
        if (wlr_output.preferredMode()) |mode| {
            state.setMode(mode);
        }
        if (!wlr_output.commitState(&state)) return;

        Output.create(wlr_output) catch {
            log.err("failed to allocate new output", .{});
            wlr_output.destroy();
            return;
        };
    }

    fn newXdgToplevel(
        _: *wl.Listener(*wlr.XdgToplevel),
        xdg_toplevel: *wlr.XdgToplevel,
    ) void {
        Toplevel.create(xdg_toplevel) catch {
            log.err("out of memory", .{});
            xdg_toplevel.resource.postNoMemory();
            return;
        };
    }

    const ToplevelAtResult = struct {
        toplevel: *Toplevel,
        surface: *wlr.Surface,
        sx: f64,
        sy: f64,
    };

    pub fn toplevelAt(self: *Server, lx: f64, ly: f64) ?ToplevelAtResult {
        var sx: f64 = undefined;
        var sy: f64 = undefined;
        if (self.scene.tree.node.at(lx, ly, &sx, &sy)) |node| {
            if (node.type != .buffer) return null;
            const scene_buffer = wlr.SceneBuffer.fromNode(node);
            const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return null;

            var it: ?*wlr.SceneTree = node.parent;
            while (it) |n| : (it = n.node.parent) {
                if (@as(?*Toplevel, @ptrFromInt(n.node.data))) |toplevel| {
                    return ToplevelAtResult{
                        .toplevel = toplevel,
                        .surface = scene_surface.surface,
                        .sx = sx,
                        .sy = sy,
                    };
                }
            }
        }
        return null;
    }

    pub fn focusToplevel(
        self: *Server,
        toplevel: *Toplevel,
        surface: *wlr.Surface,
    ) void {
        if (self.seat.keyboard_state.focused_surface) |previous_surface| {
            if (previous_surface == surface) return;
            if (wlr.XdgSurface.tryFromWlrSurface(previous_surface)) |xdg_surface| {
                if (xdg_surface.role == .toplevel) {
                    const previous_toplevel: ?*wlr.XdgToplevel = xdg_surface.role_data.toplevel;
                    if (previous_toplevel != null) {
                        _ = previous_toplevel.?.setActivated(false);
                    }
                }
            }
        }

        toplevel.scene_tree.node.raiseToTop();
        toplevel.link.remove();
        self.mapped_toplevels.prepend(toplevel);

        _ = toplevel.xdg_toplevel.setActivated(true);

        const wlr_keyboard = self.seat.getKeyboard() orelse return;
        self.seat.keyboardNotifyEnter(
            surface,
            wlr_keyboard.keycodes[0..wlr_keyboard.num_keycodes],
            &wlr_keyboard.modifiers,
        );
    }

    fn newInput(
        listener: *wl.Listener(*wlr.InputDevice),
        device: *wlr.InputDevice,
    ) void {
        const server: *Server = @fieldParentPtr("new_input", listener);
        switch (device.type) {
            .keyboard => Keyboard.create(device) catch |err| {
                log.err("failed to create keyboard: {}", .{err});
                return;
            },
            .pointer => server.cursor.wlr_cursor.attachInputDevice(device),
            else => {},
        }

        server.seat.setCapabilities(.{
            .pointer = true,
            .keyboard = server.keyboards.length() > 0,
        });
    }

    fn requestSetCursor(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
        event: *wlr.Seat.event.RequestSetCursor,
    ) void {
        const server: *Server = @fieldParentPtr("request_set_cursor", listener);
        if (event.seat_client == server.seat.pointer_state.focused_client)
            server.cursor.wlr_cursor.setSurface(
                event.surface,
                event.hotspot_x,
                event.hotspot_y,
            );
    }

    fn requestSetSelection(
        listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
        event: *wlr.Seat.event.RequestSetSelection,
    ) void {
        const server: *Server = @fieldParentPtr("request_set_selection", listener);
        server.seat.setSelection(event.source, event.serial);
    }

    /// Assumes the modifier used for compositor keybinds is pressed
    /// Returns true if the key was handled
    pub fn handleKeybind(self: *Server, key: xkb.Keysym) bool {
        switch (@intFromEnum(key)) {
            // Exit the compositor
            xkb.Keysym.Escape => self.wl_server.terminate(),
            // Focus the next toplevel in the stack, pushing the current top to the back
            xkb.Keysym.F1 => {
                if (self.mapped_toplevels.length() < 2) return true;
                const toplevel: *Toplevel = @fieldParentPtr("link", self.mapped_toplevels.link.prev.?);
                self.focusToplevel(toplevel, toplevel.xdg_toplevel.base.surface);
            },
            // Set focused toplevel to fullscreen.
            xkb.Keysym.f => {
                const toplevel: *Toplevel = @fieldParentPtr("link", self.mapped_toplevels.link.prev.?);
                if (toplevel.scene_tree.node.enabled) {
                    toplevel.xdg_toplevel.events.request_fullscreen.emit();
                }
            },
            // Set focused toplevel to maximized.
            xkb.Keysym.M => {
                const toplevel: *Toplevel = @fieldParentPtr("link", self.mapped_toplevels.link.prev.?);
                if (toplevel.scene_tree.node.enabled) {
                    toplevel.xdg_toplevel.events.request_maximize.emit();
                }
            },
            // Set focused toplevel to minimized.
            xkb.Keysym.m => {
                const toplevel: *Toplevel = @fieldParentPtr("link", self.mapped_toplevels.link.prev.?);
                if (toplevel.scene_tree.node.enabled) {
                    toplevel.xdg_toplevel.events.request_minimize.emit();
                }
            },
            else => return false,
        }
        return true;
    }
};
