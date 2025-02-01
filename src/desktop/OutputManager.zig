const std = @import("std");
const log = std.log.scoped(.@"desktop.OutputManager");
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const hwc = @import("hwc");
const server = &hwc.server;

outputs: wl.list.Head(hwc.desktop.Output, .link),

new_output: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleNewOutput),

wlr_presentation: *wlr.Presentation,
wlr_xdg_output_manager: *wlr.XdgOutputManagerV1,

wlr_output_layout: *wlr.OutputLayout,
layout_change: wl.Listener(*wlr.OutputLayout) =
    wl.Listener(*wlr.OutputLayout).init(handleLayoutChange),

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

pub fn init(self: *hwc.desktop.OutputManager) !void {
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
    self.wlr_output_layout.events.change.add(&self.layout_change);
    self.wlr_output_manager.events.apply.add(&self.apply_config);
    self.wlr_output_manager.events.@"test".add(&self.test_config);
    self.wlr_output_power_manager.events.set_mode.add(&self.set_power_mode);
    self.wlr_gamma_control_manager.events.set_gamma.add(&self.set_gamma);
}
pub fn deinit(self: *hwc.desktop.OutputManager) void {
    self.new_output.link.remove();
}

fn handleNewOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("new_output", listener);

    const output = hwc.desktop.Output.create(server.allocator, wlr_output) catch |err| {
        log.err("{s} failed: '{}': name='{s}'", .{ @src().fn_name, err, wlr_output.name });
        wlr_output.destroy();

        return;
    };

    output_manager.outputs.prepend(output);
}

fn handleLayoutChange(
    listener: *wl.Listener(*wlr.OutputLayout),
    wlr_output_layout: *wlr.OutputLayout,
) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("layout_change", listener);

    var it = output_manager.outputs.iterator(.forward);
    while (it.next()) |output| {
        var box: wlr.Box = undefined;
        wlr_output_layout.getBox(output.wlr_output, &box);

        output.wlr_scene_output.setPosition(box.x, box.y);
    }

    log.debug("{s}", .{@src().fn_name});
}

// TODO
fn handleApplyConfig(
    listener: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1,
) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("apply_config", listener);
    _ = output_manager;
    _ = config;
}

// TODO
fn handleTestConfig(
    listener: *wl.Listener(*wlr.OutputConfigurationV1),
    config: *wlr.OutputConfigurationV1,
) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("test_config", listener);
    _ = output_manager;
    _ = config;
}

// TODO
fn handleSetPowerMode(
    listener: *wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode),
    event: *wlr.OutputPowerManagerV1.event.SetMode,
) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("set_power_mode", listener);
    _ = output_manager;
    _ = event;
}

// TODO
fn handleSetGamma(
    listener: *wl.Listener(*wlr.GammaControlManagerV1.event.SetGamma),
    event: *wlr.GammaControlManagerV1.event.SetGamma,
) void {
    const output_manager: *hwc.desktop.OutputManager = @fieldParentPtr("set_gamma", listener);
    _ = output_manager;
    _ = event;
}
