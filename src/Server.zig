const std = @import("std");
const log = std.log.scoped(.server);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const hwc = @import("hwc.zig");
const c = @import("c.zig");

wl_server: *wl.Server,
backend: *wlr.Backend,
session: ?*wlr.Session,
renderer: *wlr.Renderer,
allocator: *wlr.Allocator,
scene: *wlr.Scene,

shm: *wlr.Shm,
drm: ?*wlr.Drm = null,
linux_dmabuf: ?*wlr.LinuxDmabufV1 = null,

output_layout: *wlr.OutputLayout,
scene_output_layout: *wlr.SceneOutputLayout,
new_output: wl.Listener(*wlr.Output) =
    wl.Listener(*wlr.Output).init(handleNewOutput),

xdg_shell: *wlr.XdgShell,
new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) =
    wl.Listener(*wlr.XdgToplevel).init(handleNewXdgToplevel),
mapped_toplevels: wl.list.Head(hwc.XdgToplevel, .link) = undefined,

seat: *wlr.Seat,
new_input: wl.Listener(*wlr.InputDevice) =
    wl.Listener(*wlr.InputDevice).init(handleNewInput),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) =
    wl.Listener(*wlr.Seat.event.RequestSetCursor).init(handleRequestSetCursor),
request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) =
    wl.Listener(*wlr.Seat.event.RequestSetSelection).init(handleRequestSetSelection),
keyboards: wl.list.Head(hwc.Keyboard, .link) = undefined,

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,
new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) =
    wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleNewToplevelDecoration),

config: hwc.Config,
cursor: hwc.Cursor,
output_manager: hwc.OutputManager,

/// Timer for repeating keyboard mappings
keybind_repeat_timer: *wl.EventSource,

/// Currently repeating mapping, if any
repeating_keybind: ?*const hwc.Keybind = null,

security_context_manager: *wlr.SecurityContextManagerV1,
single_pixel_buffer_manager: *wlr.SinglePixelBufferManagerV1,
viewporter: *wlr.Viewporter,
fractional_scale_manager: *wlr.FractionalScaleManagerV1,
data_device_manager: *wlr.DataDeviceManager,
primary_selection_manager: *wlr.PrimarySelectionDeviceManagerV1,
data_control_manager: *wlr.DataControlManagerV1,
export_dmabuf_manager: *wlr.ExportDmabufManagerV1,
screencopy_manager: *wlr.ScreencopyManagerV1,
xdg_output_manager: *wlr.XdgOutputManagerV1,
presentation: *wlr.Presentation,

pub fn init(self: *hwc.Server) !void {
    const wl_server = try wl.Server.create();
    const event_loop = wl_server.getEventLoop();
    var session: ?*wlr.Session = undefined;
    const backend = try wlr.Backend.autocreate(event_loop, &session);
    const renderer = try wlr.Renderer.autocreate(backend);
    const output_layout = try wlr.OutputLayout.create(wl_server);
    const scene = try wlr.Scene.create();

    const keybind_repeat_timer = try event_loop.addTimer(*hwc.Server, handleMappingRepeatTimeout, self);
    errdefer keybind_repeat_timer.remove();

    self.* = .{
        .wl_server = wl_server,
        .backend = backend,
        .session = session,
        .renderer = renderer,
        .allocator = try wlr.Allocator.autocreate(backend, renderer),
        .shm = try wlr.Shm.createWithRenderer(wl_server, 1, renderer),
        .scene = scene,
        .output_layout = output_layout,
        .scene_output_layout = try scene.attachOutputLayout(output_layout),
        .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
        .seat = try wlr.Seat.create(wl_server, "default"),
        .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server),
        .cursor = undefined,
        .output_manager = undefined,
        .config = undefined,
        .keybind_repeat_timer = keybind_repeat_timer,
        .security_context_manager = try wlr.SecurityContextManagerV1.create(wl_server),
        .single_pixel_buffer_manager = try wlr.SinglePixelBufferManagerV1.create(wl_server),
        .viewporter = try wlr.Viewporter.create(wl_server),
        .fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1),
        .data_device_manager = try wlr.DataDeviceManager.create(wl_server),
        .primary_selection_manager = try wlr.PrimarySelectionDeviceManagerV1.create(wl_server),
        .data_control_manager = try wlr.DataControlManagerV1.create(wl_server),
        .export_dmabuf_manager = try wlr.ExportDmabufManagerV1.create(wl_server),
        .screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server),
        .xdg_output_manager = try wlr.XdgOutputManagerV1.create(wl_server, output_layout),
        .presentation = try wlr.Presentation.create(wl_server, backend),
    };

    if (renderer.getTextureFormats(@intFromEnum(wlr.BufferCap.dmabuf)) != null) {
        self.drm = try wlr.Drm.create(wl_server, renderer);
        self.linux_dmabuf = try wlr.LinuxDmabufV1.createWithRenderer(wl_server, 4, renderer);
    }

    _ = try wlr.Compositor.create(self.wl_server, 6, self.renderer);
    _ = try wlr.Subcompositor.create(self.wl_server);
    _ = try wlr.DataDeviceManager.create(self.wl_server);

    self.backend.events.new_output.add(&self.new_output);

    self.xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);
    self.mapped_toplevels.init();

    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.new_toplevel_decoration);

    self.backend.events.new_input.add(&self.new_input);
    self.seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.seat.events.request_set_selection.add(&self.request_set_selection);
    self.keyboards.init();

    try self.config.init();
    try self.cursor.init();
    try self.output_manager.init();
}

pub fn deinit(self: *hwc.Server) void {
    self.keybind_repeat_timer.remove();
    self.new_xdg_toplevel.link.remove();
    self.new_toplevel_decoration.link.remove();

    self.wl_server.destroyClients();

    self.backend.destroy();

    self.renderer.destroy();
    self.allocator.destroy();

    self.cursor.deinit();

    self.wl_server.destroy();
}

pub fn start(self: *hwc.Server) !void {
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);
    try self.backend.start();
    log.info("Setting WAYLAND_DISPLAY to {s}", .{socket});
    if (c.setenv("WAYLAND_DISPLAY", socket.ptr, 1) < 0) {
        return error.SetenvError;
    }
}

const ToplevelAtResult = struct {
    toplevel: *hwc.XdgToplevel,
    surface: *wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn toplevelAt(self: *hwc.Server, lx: f64, ly: f64) ?ToplevelAtResult {
    var sx: f64 = undefined;
    var sy: f64 = undefined;
    if (self.scene.tree.node.at(lx, ly, &sx, &sy)) |node| {
        if (node.type != .buffer) return null;
        const scene_buffer = wlr.SceneBuffer.fromNode(node);
        const scene_surface = wlr.SceneSurface.tryFromBuffer(scene_buffer) orelse return null;

        var it: ?*wlr.SceneTree = node.parent;
        while (it) |n| : (it = n.node.parent) {
            if (@as(?*hwc.XdgToplevel, @ptrFromInt(n.node.data))) |toplevel| {
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
    self: *hwc.Server,
    toplevel: *hwc.XdgToplevel,
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

fn handleNewOutput(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const server: *hwc.Server = @fieldParentPtr("new_output", listener);

    const output = hwc.Output.create(wlr_output) catch |err| {
        log.err("failed to allocate new output {}", .{err});
        wlr_output.destroy();
        return;
    };

    server.output_manager.addOutput(output);
}

fn handleNewXdgToplevel(
    _: *wl.Listener(*wlr.XdgToplevel),
    xdg_toplevel: *wlr.XdgToplevel,
) void {
    hwc.XdgToplevel.create(xdg_toplevel) catch {
        log.err("out of memory", .{});
        xdg_toplevel.resource.postNoMemory();
        return;
    };
}

fn handleNewInput(
    listener: *wl.Listener(*wlr.InputDevice),
    device: *wlr.InputDevice,
) void {
    const server: *hwc.Server = @fieldParentPtr("new_input", listener);
    switch (device.type) {
        .keyboard => hwc.Keyboard.create(device) catch |err| {
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

fn handleRequestSetCursor(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor),
    event: *wlr.Seat.event.RequestSetCursor,
) void {
    const server: *hwc.Server = @fieldParentPtr("request_set_cursor", listener);
    if (event.seat_client == server.seat.pointer_state.focused_client) {
        server.cursor.wlr_cursor.setSurface(
            event.surface,
            event.hotspot_x,
            event.hotspot_y,
        );
    }
}

fn handleRequestSetSelection(
    listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection),
    event: *wlr.Seat.event.RequestSetSelection,
) void {
    const server: *hwc.Server = @fieldParentPtr("request_set_selection", listener);
    server.seat.setSelection(event.source, event.serial);
}

fn handleNewToplevelDecoration(
    _: *wl.Listener(*wlr.XdgToplevelDecorationV1),
    wlr_xdg_decoration: *wlr.XdgToplevelDecorationV1,
) void {
    hwc.XdgDecoration.init(wlr_xdg_decoration);
}

/// Repeat key mapping
fn handleMappingRepeatTimeout(self: *hwc.Server) c_int {
    if (self.repeating_keybind) |keybind| {
        const rate = self.config.keyboard_repeat_rate;
        const ms_delay = if (rate > 0) 1000 / rate else 0;
        self.keybind_repeat_timer.timerUpdate(ms_delay) catch {
            log.err("failed to update mapping repeat timer", .{});
        };
        keybind.runLuaCallback() catch {};
    }
    return 0;
}

pub fn clearRepeatingMapping(self: *hwc.Server) void {
    self.keybind_repeat_timer.timerUpdate(0) catch {
        log.err("failed to clear mapping repeat timer", .{});
    };
    self.repeating_keybind = null;
}
