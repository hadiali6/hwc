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
compositor: *wlr.Compositor,
subcompositor: *wlr.Subcompositor,
scene: *wlr.Scene,
hidden: *wlr.SceneTree,

renderer_lost: wl.Listener(void) = wl.Listener(void).init(handleRendererLost),

shm: *wlr.Shm,
drm: ?*wlr.Drm = null,
linux_dmabuf: ?*wlr.LinuxDmabufV1 = null,

output_layout: *wlr.OutputLayout,
scene_output_layout: *wlr.SceneOutputLayout,
new_output: wl.Listener(*wlr.Output) =
    wl.Listener(*wlr.Output).init(handleNewOutput),
all_outputs: wl.list.Head(hwc.Output, .link),

xdg_shell: *wlr.XdgShell,
new_xdg_toplevel: wl.Listener(*wlr.XdgToplevel) =
    wl.Listener(*wlr.XdgToplevel).init(handleNewXdgToplevel),
mapped_toplevels: wl.list.Head(hwc.XdgToplevel, .link),

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,
new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) =
    wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleNewToplevelDecoration),

config: hwc.Config,
output_manager: hwc.OutputManager,
input_manager: hwc.input.Manager,

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
    const hidden_scene_tree = try scene.tree.createSceneTree();
    hidden_scene_tree.node.setEnabled(false);

    self.* = .{
        .wl_server = wl_server,
        .backend = backend,
        .session = session,
        .renderer = renderer,
        .allocator = try wlr.Allocator.autocreate(backend, renderer),
        .compositor = try wlr.Compositor.create(self.wl_server, 6, self.renderer),
        .subcompositor = try wlr.Subcompositor.create(self.wl_server),
        .shm = try wlr.Shm.createWithRenderer(wl_server, 1, renderer),
        .scene = scene,
        .output_layout = output_layout,
        .scene_output_layout = try scene.attachOutputLayout(output_layout),
        .output_manager = undefined,
        .all_outputs = undefined,
        .xdg_shell = try wlr.XdgShell.create(wl_server, 2),
        .mapped_toplevels = undefined,
        .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(wl_server),
        .config = undefined,
        .input_manager = undefined,
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
        .hidden = hidden_scene_tree,
    };

    if (renderer.getTextureFormats(@intFromEnum(wlr.BufferCap.dmabuf)) != null) {
        self.drm = try wlr.Drm.create(wl_server, renderer);
        self.linux_dmabuf = try wlr.LinuxDmabufV1.createWithRenderer(wl_server, 4, renderer);
    }

    self.all_outputs.init();

    self.renderer.events.lost.add(&self.renderer_lost);
    self.backend.events.new_output.add(&self.new_output);

    self.xdg_shell.events.new_toplevel.add(&self.new_xdg_toplevel);
    self.mapped_toplevels.init();

    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.new_toplevel_decoration);

    try self.config.init();
    try self.output_manager.init();
    try self.input_manager.init();
}

pub fn deinit(self: *hwc.Server) void {
    self.new_xdg_toplevel.link.remove();
    self.new_toplevel_decoration.link.remove();

    self.wl_server.destroyClients();

    self.backend.destroy();

    self.renderer.destroy();
    self.allocator.destroy();

    self.input_manager.deinit();

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

const AtResult = struct {
    wlr_scene_node: *wlr.SceneNode,
    wlr_surface: ?*wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn resultAt(self: *hwc.Server, lx: f64, ly: f64) ?AtResult {
    var sx: f64 = undefined;
    var sy: f64 = undefined;
    const wlr_scene_node = self.scene.tree.node.at(lx, ly, &sx, &sy) orelse return null;

    const wlr_surface: ?*wlr.Surface = blk: {
        if (wlr_scene_node.type == .buffer) {
            const wlr_scene_buffer = wlr.SceneBuffer.fromNode(wlr_scene_node);

            if (wlr.SceneSurface.tryFromBuffer(wlr_scene_buffer)) |wlr_scene_surface| {
                break :blk wlr_scene_surface.surface;
            }
        }

        break :blk null;
    };

    return .{
        .wlr_scene_node = wlr_scene_node,
        .wlr_surface = wlr_surface,
        .sx = sx,
        .sy = sy,
    };
}

fn handleNewOutput(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const server: *hwc.Server = @fieldParentPtr("new_output", listener);

    hwc.Output.create(wlr_output) catch |err| {
        log.err("failed to allocate new output {}", .{err});
        wlr_output.destroy();
        return;
    };

    server.output_manager.addOutput();
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

fn handleNewToplevelDecoration(
    _: *wl.Listener(*wlr.XdgToplevelDecorationV1),
    wlr_xdg_decoration: *wlr.XdgToplevelDecorationV1,
) void {
    hwc.XdgDecoration.init(wlr_xdg_decoration);
}

fn handleRendererLost(listener: *wl.Listener(void)) void {
    const server: *hwc.Server = @fieldParentPtr("renderer_lost", listener);

    const new_renderer = wlr.Renderer.autocreate(server.backend) catch {
        log.err("failed to create new renderer after GPU reset", .{});
        return;
    };

    const new_allocator = wlr.Allocator.autocreate(server.backend, server.renderer) catch {
        new_renderer.destroy();
        log.err("failed to create new allocator after GPU reset", .{});
        return;
    };

    server.renderer_lost.link.remove();
    new_renderer.events.lost.add(&server.renderer_lost);

    server.compositor.setRenderer(new_renderer);

    {
        var iterator = server.all_outputs.iterator(.forward);
        while (iterator.next()) |output| {
            _ = output.wlr_output.initRender(new_allocator, new_renderer);
        }
    }

    server.renderer.destroy();
    server.renderer = new_renderer;

    server.allocator.destroy();
    server.allocator = new_allocator;
}
