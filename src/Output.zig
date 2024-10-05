const std = @import("std");
const log = std.log.scoped(.output);

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");
const hwc = @import("hwc.zig");

const server = &@import("root").server;

link: wl.list.Link,
wlr_output: *wlr.Output,
/// The previous configuration applied to the output, used for cancelling failed
/// configurations. This is reset after all outputs have been succesfully
/// configured.
previous_config: ?wlr.OutputHeadV1.State = null,
/// The new configuration waiting to be applied on the next commit.
pending_config: ?wlr.OutputHeadV1.State = null,

frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleFrame),
request_state: wl.Listener(*wlr.Output.event.RequestState) =
    wl.Listener(*wlr.Output.event.RequestState).init(handleRequestState),
destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleDestroy),

// The wlr.Output should be destroyed by the caller on failure to trigger cleanup.
pub fn create(wlr_output: *wlr.Output) !*hwc.Output {
    if (!wlr_output.initRender(server.allocator, server.renderer)) {
        return error.InitRenderFailed;
    }
    {
        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(true);

        if (wlr_output.preferredMode()) |mode| {
            log.info("initial output commit with perferred mode succeeded with mode {}x{}@{}mHz", .{
                mode.width,
                mode.height,
                mode.refresh,
            });
            state.setMode(mode);
        }

        if (!wlr_output.commitState(&state)) {
            log.err("initial output commit with preferred mode failed, trying all modes", .{});
            var iterator = wlr_output.modes.iterator(.forward);
            while (iterator.next()) |mode| {
                state.setMode(mode);
                if (wlr_output.commitState(&state)) {
                    log.info("initial output commit succeeded with mode {}x{}@{}mHz", .{
                        mode.width,
                        mode.height,
                        mode.refresh,
                    });
                    break;
                } else {
                    log.err("initial output commit failed with mode {}x{}@{}mHz", .{
                        mode.width,
                        mode.height,
                        mode.refresh,
                    });
                }
            }
        }
    }

    const output = try util.allocator.create(hwc.Output);
    errdefer util.allocator.destroy(output);

    output.* = .{
        .link = undefined,
        .wlr_output = wlr_output,
    };

    wlr_output.events.frame.add(&output.frame);
    wlr_output.events.request_state.add(&output.request_state);
    wlr_output.events.destroy.add(&output.destroy);

    const layout_output = try server.output_layout.addAuto(wlr_output);
    errdefer server.output_layout.remove(wlr_output);

    const scene_output = try server.scene.createSceneOutput(wlr_output);
    errdefer scene_output.destroy();

    server.scene_output_layout.addOutput(layout_output, scene_output);

    wlr_output.data = @intFromPtr(output);

    return output;
}

/// Return the current configuration of the output.
fn getCurrentConfig(output: *const hwc.Output) wlr.OutputHeadV1.State {
    const wlr_output = output.wlr_output;
    const layout_output = server.output_layout.get(wlr_output);
    return .{
        .output = wlr_output,
        .enabled = wlr_output.enabled,
        .mode = wlr_output.current_mode,
        .custom_mode = .{
            .width = wlr_output.width,
            .height = wlr_output.height,
            .refresh = wlr_output.refresh,
        },
        .x = if (layout_output) |l_output| l_output.x else undefined,
        .y = if (layout_output) |l_output| l_output.y else undefined,
        .transform = wlr_output.transform,
        .scale = wlr_output.scale,
        .adaptive_sync_enabled = wlr_output.adaptive_sync_status == .enabled,
    };
}

/// Create a prefilled configuration head for the output.
pub fn createHead(
    output: *const hwc.Output,
    config: *wlr.OutputConfigurationV1,
) !*wlr.OutputConfigurationV1.Head {
    const head = try wlr.OutputConfigurationV1.Head.create(config, output.wlr_output);
    head.state = output.getCurrentConfig();
    return head;
}

/// Commit a new configuration to the output.
pub fn commitConfig(output: *hwc.Output, config: *const wlr.OutputHeadV1.State) !void {
    const scene = server.scene;
    const scene_output = scene.getSceneOutput(output.wlr_output).?;
    const wlr_output = output.wlr_output;

    log.debug("Committing changes for output {s}", .{wlr_output.name});
    if (config.enabled) {
        const layout_output = try server.output_layout.add(wlr_output, config.x, config.y);
        errdefer server.output_layout.remove(wlr_output);
        if (!wlr_output.enabled) {
            log.debug("Enabling output {s}", .{wlr_output.name});
            server.scene_output_layout.addOutput(layout_output, scene_output);
        }
        var new_width: u31 = @intFromFloat(
            @as(
                f32,
                @floatFromInt(if (config.mode) |mode|
                    mode.width
                else
                    config.custom_mode.width),
            ) / config.scale,
        );
        var new_height: u31 = @intFromFloat(
            @as(
                f32,
                @floatFromInt(if (config.mode) |mode|
                    mode.height
                else
                    config.custom_mode.height),
            ) / config.scale,
        );
        if (@rem(@intFromEnum(config.transform), 2) != 0) {
            const tmp = new_width;
            new_width = new_height;
            new_height = tmp;
        }
    } else {
        log.debug("Disabling output {s}", .{wlr_output.name});
        server.output_layout.remove(wlr_output);
    }
    var output_state = wlr.Output.State.init();
    defer output_state.finish();
    config.apply(&output_state);
    if (!scene_output.buildState(&output_state, null) or
        !wlr_output.commitState(&output_state))
    {
        log.debug("Commit failed for output {s}", .{wlr_output.name});
        return error.OutputCommitFailed;
    }
}

fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const output: *hwc.Output = @fieldParentPtr("frame", listener);

    const scene_output = server.scene.getSceneOutput(output.wlr_output).?;

    if (output.pending_config) |pending_config| {
        output.previous_config = output.getCurrentConfig();

        output.commitConfig(&pending_config) catch {
            output.pending_config = null;
            output.previous_config = null;
            server.output_manager.cancelConfiguration();
            return;
        };

        output.pending_config = null;
        server.output_manager.pending_outputs -= 1;

        if (server.output_manager.pending_outputs == 0) {
            server.output_manager.finishConfiguration();
        }
    } else {
        _ = scene_output.commit(null);
    }

    var now: std.posix.timespec = undefined;
    std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC, &now) catch {
        @panic("CLOCK_MONOTONIC not supported");
    };
    scene_output.sendFrameDone(&now);
}

fn handleRequestState(
    listener: *wl.Listener(*wlr.Output.event.RequestState),
    event: *wlr.Output.event.RequestState,
) void {
    const output: *hwc.Output = @fieldParentPtr("request_state", listener);
    _ = output.wlr_output.commitState(event.state);
}

fn handleDestroy(
    listener: *wl.Listener(*wlr.Output),
    wlr_output: *wlr.Output,
) void {
    const output: *hwc.Output = @fieldParentPtr("destroy", listener);

    output.link.remove();

    if (output.pending_config != null or output.previous_config != null) {
        const output_manager = &server.output_manager;
        output_manager.cancelConfiguration();
    }

    output.request_state.link.remove();
    output.frame.link.remove();
    output.destroy.link.remove();

    wlr_output.data = 0;

    util.allocator.destroy(output);
}
