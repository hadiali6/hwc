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

const hwc = @import("hwc");

allocator: mem.Allocator,

wl_server: *wl.Server,

sig_interrupt_source: *wl.EventSource,
sig_terminate_source: *wl.EventSource,

wlr_backend: *wlr.Backend,
wlr_session: ?*wlr.Session,

wlr_renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
wlr_shm: *wlr.Shm,

renderer_lost: wl.Listener(void) = wl.Listener(void).init(handleRendererLost),

wlr_drm: ?*wlr.Drm = null,
wlr_linux_dmabuf: ?*wlr.LinuxDmabufV1 = null,

wlr_compositor: *wlr.Compositor,
wlr_subcompositor: *wlr.Subcompositor,
wlr_data_device_manager: *wlr.DataDeviceManager,

wlr_alpha_modifier: *wlr.AlphaModifierV1,
wlr_content_type_manager: *wlr.ContentTypeManagerV1,
wlr_data_control_manager: *wlr.DataControlManagerV1,
wlr_export_dmabuf_manager: *wlr.ExportDmabufManagerV1,
wlr_fractional_scale_manager: *wlr.FractionalScaleManagerV1,
wlr_primary_selection_device_manager: *wlr.PrimarySelectionDeviceManagerV1,
wlr_screencopy_manager: *wlr.ScreencopyManagerV1,
wlr_security_context_manager: *wlr.SecurityContextManagerV1,
wlr_single_pixel_buffer_manager: *wlr.SinglePixelBufferManagerV1,
wlr_viewporter: *wlr.Viewporter,

output_manager: hwc.desktop.OutputManager,
surface_manager: hwc.desktop.SurfaceManager,
input_manager: hwc.input.Manager,
status_manager: hwc.StatusManager,

pub fn init(self: *hwc.Server, allocator: mem.Allocator) !void {
    const wl_server = try wl.Server.create();
    const wl_event_loop = wl_server.getEventLoop();

    var wlr_session: ?*wlr.Session = undefined;
    const wlr_backend = try wlr.Backend.autocreate(wl_event_loop, &wlr_session);

    const wlr_renderer = try wlr.Renderer.autocreate(wlr_backend);

    self.* = .{
        .allocator = allocator,
        .wl_server = wl_server,

        .sig_interrupt_source = try wl_event_loop.addSignal(
            *wl.Server,
            posix.SIG.INT,
            handleDestroySingals,
            wl_server,
        ),
        .sig_terminate_source = try wl_event_loop.addSignal(
            *wl.Server,
            posix.SIG.TERM,
            handleDestroySingals,
            wl_server,
        ),

        .wlr_backend = wlr_backend,
        .wlr_session = wlr_session,

        .wlr_renderer = wlr_renderer,
        .wlr_allocator = try wlr.Allocator.autocreate(wlr_backend, wlr_renderer),
        .wlr_shm = try wlr.Shm.createWithRenderer(wl_server, 2, wlr_renderer),

        .wlr_compositor = try wlr.Compositor.create(wl_server, 6, wlr_renderer),
        .wlr_subcompositor = try wlr.Subcompositor.create(wl_server),
        .wlr_data_device_manager = try wlr.DataDeviceManager.create(wl_server),

        .wlr_alpha_modifier = try wlr.AlphaModifierV1.create(wl_server),
        .wlr_data_control_manager = try wlr.DataControlManagerV1.create(wl_server),
        .wlr_export_dmabuf_manager = try wlr.ExportDmabufManagerV1.create(wl_server),
        .wlr_fractional_scale_manager = try wlr.FractionalScaleManagerV1.create(wl_server, 1),
        .wlr_primary_selection_device_manager = try wlr.PrimarySelectionDeviceManagerV1.create(wl_server),
        .wlr_screencopy_manager = try wlr.ScreencopyManagerV1.create(wl_server),
        .wlr_security_context_manager = try wlr.SecurityContextManagerV1.create(wl_server),
        .wlr_single_pixel_buffer_manager = try wlr.SinglePixelBufferManagerV1.create(wl_server),
        .wlr_viewporter = try wlr.Viewporter.create(wl_server),
        .wlr_content_type_manager = try wlr.ContentTypeManagerV1.create(wl_server, 1),

        .output_manager = undefined,
        .surface_manager = undefined,
        .input_manager = undefined,
        .status_manager = undefined,
    };

    try self.surface_manager.init();

    if (wlr_renderer.getTextureFormats(@intFromEnum(wlr.BufferCap.dmabuf)) != null) {
        // TODO: remove because wl_drm is a legacy interface
        self.wlr_drm = try wlr.Drm.create(wl_server, wlr_renderer);
        self.wlr_linux_dmabuf =
            try wlr.LinuxDmabufV1.createWithRenderer(wl_server, 5, wlr_renderer);
        self.surface_manager.wlr_scene.setLinuxDmabufV1(self.wlr_linux_dmabuf.?);
    }

    try self.output_manager.init();
    try self.input_manager.init();
    try self.status_manager.init();

    wlr_renderer.events.lost.add(&self.renderer_lost);

    wl_server.setGlobalFilter(*hwc.Server, handleGlobalFilter, self);

    log.info("{s}", .{@src().fn_name});
}

pub fn deinit(self: *hwc.Server) void {
    self.sig_interrupt_source.remove();
    self.sig_terminate_source.remove();

    self.renderer_lost.link.remove();

    self.wl_server.destroyClients();

    self.input_manager.deinit();
    self.output_manager.deinit();

    self.wlr_backend.destroy();

    assert(self.output_manager.outputs.empty());

    self.surface_manager.deinit();
    self.wlr_renderer.destroy();
    self.wlr_allocator.destroy();

    self.wl_server.destroy();

    log.info("{s}", .{@src().fn_name});
}

pub fn startSocket(self: *hwc.Server) !void {
    const socket = blk: {
        var buf: [11]u8 = undefined;
        break :blk try self.wl_server.addSocketAuto(&buf);
    };

    if (libc.setenv("WAYLAND_DISPLAY", socket.ptr, 1) < 0) {
        return error.SetenvFailed;
    }

    log.info("{s}: set WAYLAND_DISPLAY={s}", .{ @src().fn_name, socket });
}

pub fn start(self: *hwc.Server) !void {
    try self.wlr_backend.start();
    self.wl_server.run();
}

fn handleGlobalFilter(
    wl_client: *const wl.Client,
    wl_global: *const wl.Global,
    server: *hwc.Server,
) bool {
    if (server.wlr_security_context_manager.lookupClient(wl_client)) |wlr_security_context_state| {
        const allowed = server.isAllowed(wl_global);
        const blocked = server.isBlocked(wl_global);

        log.debug("{s}: global='{s}' allowed='{}' sandbox_engine='{s}' app_id='{s}' instance_id='{s}'", .{
            @src().fn_name,
            wl_global.getInterface().name,
            allowed,
            wlr_security_context_state.app_id orelse "unknown",
            wlr_security_context_state.app_id orelse "unknown",
            wlr_security_context_state.instance_id orelse "unknown",
        });

        assert(blocked != allowed);

        return allowed;
    } else {
        log.debug(
            "{s}: global='{s}' allowed='true'",
            .{ @src().fn_name, wl_global.getInterface().name },
        );
        return true;
    }
}

fn isAllowed(self: *hwc.Server, wl_global: *const wl.Global) bool {
    if (self.wlr_drm) |wlr_drm| {
        return wl_global == wlr_drm.global;
    }

    if (self.wlr_linux_dmabuf) |wlr_linux_dmabuf| {
        return wl_global == wlr_linux_dmabuf.global;
    }

    return mem.orderZ(u8, wl_global.getInterface().name, "wl_output") == .eq or
        mem.orderZ(u8, wl_global.getInterface().name, "wl_seat") == .eq or
        wl_global == self.input_manager.wlr_pointer_gestures.global or
        wl_global == self.input_manager.wlr_relative_pointer_manager.global or
        wl_global == self.output_manager.wlr_presentation.global or
        wl_global == self.output_manager.wlr_xdg_output_manager.global or
        wl_global == self.surface_manager.wlr_xdg_shell.global or
        wl_global == self.wlr_alpha_modifier.global or
        wl_global == self.wlr_compositor.global or
        wl_global == self.wlr_content_type_manager.global or
        wl_global == self.wlr_data_device_manager.global or
        wl_global == self.wlr_fractional_scale_manager.global or
        wl_global == self.wlr_primary_selection_device_manager.global or
        wl_global == self.wlr_shm.global or
        wl_global == self.wlr_single_pixel_buffer_manager.global or
        wl_global == self.wlr_subcompositor.global or
        wl_global == self.wlr_viewporter.global;
}

fn isBlocked(self: *hwc.Server, wl_global: *const wl.Global) bool {
    return wl_global == self.output_manager.wlr_gamma_control_manager.global or
        wl_global == self.output_manager.wlr_output_manager.global or
        wl_global == self.output_manager.wlr_output_power_manager.global or
        wl_global == self.status_manager.global or
        wl_global == self.surface_manager.wlr_foreign_toplevel_manager.global or
        wl_global == self.surface_manager.wlr_layer_shell.global or
        wl_global == self.wlr_data_control_manager.global or
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

fn handleRendererLost(listener: *wl.Listener(void)) void {
    const server: *hwc.Server = @fieldParentPtr("renderer_lost", listener);

    const new_renderer = wlr.Renderer.autocreate(server.wlr_backend) catch |err| {
        log.err(
            "{s}: '{}': failed to create new renderer after GPU reset",
            .{ @src().fn_name, err },
        );
        return;
    };

    const new_allocator = wlr.Allocator.autocreate(
        server.wlr_backend,
        server.wlr_renderer,
    ) catch |err| {
        new_renderer.destroy();
        log.err(
            "{s}: '{}': failed to create new allocator after GPU reset",
            .{ @src().fn_name, err },
        );
        return;
    };

    server.renderer_lost.link.remove();
    new_renderer.events.lost.add(&server.renderer_lost);

    server.wlr_compositor.setRenderer(new_renderer);
    {
        var it = server.output_manager.outputs.iterator(.forward);
        while (it.next()) |output| {
            _ = output.wlr_output.initRender(new_allocator, new_renderer);
        }
    }

    server.wlr_renderer.destroy();
    server.wlr_renderer = new_renderer;

    server.wlr_allocator.destroy();
    server.wlr_allocator = new_allocator;
}
