const std = @import("std");
const log = std.log.scoped(.Server);
const assert = std.debug.assert;
const mem = std.mem;
const posix = std.posix;

const libc = @cImport({
    @cInclude("stdlib.h");
});
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");

allocator: mem.Allocator,

wl_server: *wl.Server,

sigint_source: *wl.EventSource,
sigterm_source: *wl.EventSource,

wlr_backend: *wlr.Backend,
wlr_session: ?*wlr.Session,

all_outputs: wl.list.Head(hwc.Output, .link),
new_output: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleNewOutput),

wlr_renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
wlr_shm: *wlr.Shm,

wlr_drm: ?*wlr.Drm = null,
wlr_linux_dmabuf: ?*wlr.LinuxDmabufV1 = null,

wlr_scene: *wlr.Scene,
wlr_output_layout: *wlr.OutputLayout,
wlr_scene_output_layout: *wlr.SceneOutputLayout,

wlr_compositor: *wlr.Compositor,
wlr_subcompositor: *wlr.Subcompositor,
wlr_data_device_manager: *wlr.DataDeviceManager,

wlr_alpha_modifier: *wlr.AlphaModifierV1,
wlr_content_type_manager: *wlr.ContentTypeManagerV1,
wlr_data_control_manager: *wlr.DataControlManagerV1,
wlr_export_dmabuf_manager: *wlr.ExportDmabufManagerV1,
wlr_fractional_scale_manager: *wlr.FractionalScaleManagerV1,
wlr_presentation: *wlr.Presentation,
wlr_primary_selection_manager: *wlr.PrimarySelectionDeviceManagerV1,
wlr_screencopy_manager: *wlr.ScreencopyManagerV1,
wlr_security_context_manager: *wlr.SecurityContextManagerV1,
wlr_single_pixel_buffer_manager: *wlr.SinglePixelBufferManagerV1,
wlr_viewporter: *wlr.Viewporter,
wlr_xdg_output_manager: *wlr.XdgOutputManagerV1,

pub fn init(self: *hwc.Server, allocator: mem.Allocator) !void {
    wlr.log.init(.info, null);

    const wl_server = try wl.Server.create();
    const wl_event_loop = wl_server.getEventLoop();

    var wlr_session: ?*wlr.Session = undefined;
    const wlr_backend = try wlr.Backend.autocreate(wl_event_loop, &wlr_session);

    const wlr_renderer = try wlr.Renderer.autocreate(wlr_backend);
    const wlr_scene = try wlr.Scene.create();
    const wlr_output_layout = try wlr.OutputLayout.create(wl_server);

    self.* = .{
        .allocator = allocator,
        .wl_server = wl_server,

        .sigint_source = try wl_event_loop.addSignal(
            *wl.Server,
            posix.SIG.INT,
            handleDestroySingals,
            wl_server,
        ),
        .sigterm_source = try wl_event_loop.addSignal(
            *wl.Server,
            posix.SIG.TERM,
            handleDestroySingals,
            wl_server,
        ),

        .wlr_backend = wlr_backend,
        .wlr_session = wlr_session,
        .all_outputs = undefined,

        .wlr_renderer = wlr_renderer,
        .wlr_allocator = try wlr.Allocator.autocreate(wlr_backend, wlr_renderer),
        .wlr_shm = try wlr.Shm.createWithRenderer(wl_server, 2, wlr_renderer),

        .wlr_scene = wlr_scene,
        .wlr_output_layout = wlr_output_layout,
        .wlr_scene_output_layout = try wlr_scene.attachOutputLayout(wlr_output_layout),

        .wlr_compositor = try wlr.Compositor.create(wl_server, 6, wlr_renderer),
        .wlr_subcompositor = try wlr.Subcompositor.create(wl_server),
        .wlr_data_device_manager = try wlr.DataDeviceManager.create(wl_server),

        .wlr_alpha_modifier = try wlr.AlphaModifierV1.create(wl_server),
        .wlr_data_control_manager = try wlr.DataControlManagerV1.create(wl_server),
        .wlr_export_dmabuf_manager = try wlr.ExportDmabufManagerV1.create(wl_server),
        .wlr_fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1),
        .wlr_presentation = try wlr.Presentation.create(wl_server, wlr_backend),
        .wlr_primary_selection_manager = try wlr.PrimarySelectionDeviceManagerV1.create(wl_server),
        .wlr_screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server),
        .wlr_security_context_manager = try wlr.SecurityContextManagerV1.create(wl_server),
        .wlr_single_pixel_buffer_manager = try wlr.SinglePixelBufferManagerV1.create(wl_server),
        .wlr_viewporter = try wlr.Viewporter.create(wl_server),
        .wlr_xdg_output_manager = try wlr.XdgOutputManagerV1.create(wl_server, wlr_output_layout),
        .wlr_content_type_manager = try wlr.ContentTypeManagerV1.create(wl_server, 1),
    };

    if (wlr_renderer.getTextureFormats(@intFromEnum(wlr.BufferCap.dmabuf)) != null) {
        // TODO: remove because wl_drm is a legacy interface
        self.wlr_drm = try wlr.Drm.create(wl_server, wlr_renderer);
        self.wlr_linux_dmabuf =
            try wlr.LinuxDmabufV1.createWithRenderer(wl_server, 5, wlr_renderer);
    }

    self.all_outputs.init();

    wlr_backend.events.new_output.add(&self.new_output);

    wl_server.setGlobalFilter(*hwc.Server, handleGlobalFilter, self);

    log.info("{s}", .{@src().fn_name});
}

pub fn deinit(self: *hwc.Server) void {
    self.sigint_source.remove();
    self.sigterm_source.remove();

    self.new_output.link.remove();

    self.wl_server.destroyClients();

    self.wlr_backend.destroy();

    self.wlr_scene.tree.node.destroy();

    self.wlr_renderer.destroy();
    self.wlr_allocator.destroy();

    self.wl_server.destroy();

    log.info("{s}", .{@src().fn_name});
    assert(self.all_outputs.empty());
}

pub fn start(self: *hwc.Server) !void {
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);
    log.info("{s}: setting WAYLAND_DISPLAY={s}", .{ @src().fn_name, socket });

    try self.wlr_backend.start();

    if (libc.setenv("WAYLAND_DISPLAY", socket.ptr, 1) < 0) {
        return error.SetenvFailed;
    }

    log.info("{s}", .{@src().fn_name});
}

fn handleGlobalFilter(
    wl_client: *const wl.Client,
    wl_global: *const wl.Global,
    server: *hwc.Server,
) bool {
    if (server.wlr_security_context_manager.lookupClient(wl_client) != null) {
        const allowed = server.allowList(wl_global);
        const blocked = server.blockList(wl_global);

        assert(blocked != allowed);

        return allowed;
    } else {
        return true;
    }
}

fn allowList(self: *hwc.Server, wl_global: *const wl.Global) bool {
    if (self.wlr_drm) |wlr_drm| {
        return wl_global == wlr_drm.global;
    }

    if (self.wlr_linux_dmabuf) |wlr_linux_dmabuf| {
        return wl_global == wlr_linux_dmabuf.global;
    }

    return mem.orderZ(u8, wl_global.getInterface().name, "wl_output") == .eq or
        mem.orderZ(u8, wl_global.getInterface().name, "wl_seat") == .eq or
        wl_global == self.wlr_alpha_modifier.global or
        wl_global == self.wlr_compositor.global or
        wl_global == self.wlr_content_type_manager.global or
        wl_global == self.wlr_data_device_manager.global or
        wl_global == self.wlr_fractional_scale_manager.global or
        wl_global == self.wlr_presentation.global or
        wl_global == self.wlr_primary_selection_manager.global or
        wl_global == self.wlr_shm.global or
        wl_global == self.wlr_single_pixel_buffer_manager.global or
        wl_global == self.wlr_subcompositor.global or
        wl_global == self.wlr_viewporter.global or
        wl_global == self.wlr_xdg_output_manager.global;
}

fn blockList(self: *hwc.Server, wl_global: *const wl.Global) bool {
    return wl_global == self.wlr_data_control_manager.global or
        wl_global == self.wlr_export_dmabuf_manager.global or
        wl_global == self.wlr_screencopy_manager.global or
        wl_global == self.wlr_security_context_manager.global;
}

/// Handle SIGINT and SIGTERM by gracefully stopping the server
fn handleDestroySingals(signal: c_int, wl_server: *wl.Server) c_int {
    switch (signal) {
        posix.SIG.INT => log.info("{s}: handling SIGINT", .{@src().fn_name}),
        posix.SIG.TERM => log.info("{s}: handling SIGTERM", .{@src().fn_name}),
        else => unreachable,
    }

    wl_server.terminate();

    return 0;
}

fn handleNewOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const server: *hwc.Server = @fieldParentPtr("new_output", listener);

    hwc.Output.create(server.allocator, wlr_output) catch |err| {
        log.err("{s} failed: '{s}' {}", .{ @src().fn_name, wlr_output.name, err });
        wlr_output.destroy();
    };

    log.info("{s}: '{s}'", .{ @src().fn_name, wlr_output.name });
}
