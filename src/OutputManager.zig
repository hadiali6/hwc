const std = @import("std");
const log = std.log.scoped(.OutputManager);
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

outputs: wl.list.Head(hwc.Output, .link),

new_output: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleNewOutput),

wlr_presentation: *wlr.Presentation,
wlr_output_layout: *wlr.OutputLayout,
wlr_xdg_output_manager: *wlr.XdgOutputManagerV1,

wlr_output_manager: *wlr.OutputManagerV1,
apply_config: wl.Listener(*wlr.OutputConfigurationV1) =
    wl.Listener(*wlr.OutputConfigurationV1).init(handleApplyConfig),
test_config: wl.Listener(*wlr.OutputConfigurationV1) =
    wl.Listener(*wlr.OutputConfigurationV1).init(handleTestConfig),

wlr_gamma_control_manager: *wlr.GammaControlManagerV1,
set_gamma: wl.Listener(*wlr.GammaControlManagerV1.event.SetGamma) =
    wl.Listener(*wlr.GammaControlManagerV1.event.SetGamma).init(handleSetGamma),

wlr_output_power_manager: *wlr.OutputPowerManagerV1,
set_power_mode: wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode) =
    wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode).init(handleSetPowerMode),

pub fn init(self: *hwc.OutputManager) !void {
    const wlr_output_layout = try wlr.OutputLayout.create(server.wl_server);

    self.* = .{
        .outputs = undefined,
        .wlr_output_layout = wlr_output_layout,

        .wlr_presentation = try wlr.Presentation.create(server.wl_server, server.wlr_backend),
        .wlr_xdg_output_manager = try wlr.XdgOutputManagerV1.create(server.wl_server, wlr_output_layout),
        .wlr_output_manager = try wlr.OutputManagerV1.create(server.wl_server),
        .wlr_output_power_manager = try wlr.OutputPowerManagerV1.create(server.wl_server),
        .wlr_gamma_control_manager = try wlr.GammaControlManagerV1.create(server.wl_server),
    };

    self.outputs.init();

    server.wlr_backend.events.new_output.add(&self.new_output);
}
pub fn deinit(self: *hwc.OutputManager) void {
    self.new_output.link.remove();
    assert(self.outputs.empty());
}

fn handleNewOutput(_: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    hwc.Output.create(server.allocator, wlr_output) catch |err| {
        log.err("{s} failed: '{s}' {}", .{ @src().fn_name, wlr_output.name, err });
        wlr_output.destroy();
    };

    log.info("{s}: '{s}'", .{ @src().fn_name, wlr_output.name });
}

fn handleApplyConfig(
    listener: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1,
) void {
    const output_manager: *hwc.OutputManager = @fieldParentPtr("apply_config", listener);
    _ = output_manager;
    _ = config;
}

fn handleTestConfig(
    listener: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1,
) void {
    const output_manager: *hwc.OutputManager = @fieldParentPtr("test_config", listener);
    _ = output_manager;
    _ = config;
}

fn handleSetPowerMode(
    listener: *wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode),
    event: *wlr.OutputPowerManagerV1.event.SetMode,
) void {
    const output_manager: *hwc.OutputManager = @fieldParentPtr("set_power_mode", listener);
    _ = output_manager;
    _ = event;
}

fn handleSetGamma(
    listener: *wl.Listener(*wlr.GammaControlManagerV1.event.SetGamma),
    event: *wlr.GammaControlManagerV1.event.SetGamma,
) void {
    const output_manager: *hwc.OutputManager = @fieldParentPtr("set_gamma", listener);
    _ = output_manager;
    _ = event;
}
