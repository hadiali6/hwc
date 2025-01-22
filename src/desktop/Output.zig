const std = @import("std");
const log = std.log.scoped(.@"desktop.Output");
const fmt = std.fmt;
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const zwlr = wayland.server.zwlr;
const wlr = @import("wlroots");

const hwc = @import("root");
const server = &hwc.server;

link: wl.list.Link,
wlr_output: *wlr.Output,
wlr_scene_output: *wlr.SceneOutput,

layers: struct {
    background: *wlr.SceneTree,
    bottom: *wlr.SceneTree, // TODO: layer(s) for windows
    top: *wlr.SceneTree,
    overlay: *wlr.SceneTree,
    popups: *wlr.SceneTree,
},

destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleDestroy),
frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleFrame),
request_state: wl.Listener(*wlr.Output.event.RequestState) =
    wl.Listener(*wlr.Output.event.RequestState).init(handleRequestState),

pub fn create(allocator: mem.Allocator, wlr_output: *wlr.Output) !void {
    const output = try allocator.create(hwc.desktop.Output);
    errdefer allocator.destroy(output);

    {
        const window_title = try fmt.allocPrintZ(allocator, "hwc - {s}", .{wlr_output.name});
        defer allocator.free(window_title);

        if (wlr_output.isWl()) {
            wlr_output.wlSetTitle(window_title);
        }
    }

    {
        const render_successful = wlr_output.initRender(server.wlr_allocator, server.wlr_renderer);
        if (!render_successful) {
            return error.InitRenderFailed;
        }
    }

    {
        var state = wlr.Output.State.init();
        defer state.finish();

        state.setEnabled(true);

        if (wlr_output.preferredMode()) |preferred_mode| {
            state.setMode(preferred_mode);
        }

        const commit_successful = wlr_output.commitState(&state);
        if (!commit_successful) {
            log.err(
                "{s}: initial output commit with preferred mode failed, trying all modes: name='{s}'",
                .{ @src().fn_name, wlr_output.name },
            );

            var it = wlr_output.modes.iterator(.forward);
            while (it.next()) |mode| {
                state.setMode(mode);

                if (wlr_output.commitState(&state)) {
                    log.info(
                        "{s}: initial output commit succeeded with mode {}x{}@{}mHz: name='{s}'",
                        .{ @src().fn_name, mode.width, mode.height, mode.refresh, wlr_output.name },
                    );
                    break;
                } else {
                    log.err(
                        "{s}: initial output commit failed with mode {}x{}@{}mHz: name='{s}'",
                        .{ @src().fn_name, mode.width, mode.height, mode.refresh, wlr_output.name },
                    );
                }
            }
        }
    }

    const wlr_scene_output = try server.wlr_scene.createSceneOutput(wlr_output);
    errdefer wlr_scene_output.destroy();

    output.* = .{
        .link = undefined,
        .wlr_output = wlr_output,
        .wlr_scene_output = wlr_scene_output,

        .layers = .{
            .background = try server.wlr_scene.tree.createSceneTree(),
            .bottom = try server.wlr_scene.tree.createSceneTree(),
            .top = try server.wlr_scene.tree.createSceneTree(),
            .overlay = try server.wlr_scene.tree.createSceneTree(),
            .popups = try server.wlr_scene.tree.createSceneTree(),
        },
    };
    errdefer {
        output.layers.background.node.destroy();
        output.layers.bottom.node.destroy();
        output.layers.top.node.destroy();
        output.layers.overlay.node.destroy();
        output.layers.popups.node.destroy();
    }

    wlr_output.data = @intFromPtr(output);

    wlr_output.events.destroy.add(&output.destroy);
    wlr_output.events.frame.add(&output.frame);
    wlr_output.events.request_state.add(&output.request_state);

    _ = try server.output_manager.wlr_output_layout.addAuto(wlr_output);
    errdefer server.output_manager.wlr_output_layout.remove(wlr_output);

    server.output_manager.outputs.prepend(output);

    log.info("{s}: name='{s}'", .{ @src().fn_name, wlr_output.name });
}

pub fn layerSurfaceTree(self: hwc.desktop.Output, layer: zwlr.LayerShellV1.Layer) *wlr.SceneTree {
    return switch (layer) {
        .background => self.layers.background,
        .bottom => self.layers.bottom,
        .top => self.layers.top,
        .overlay => self.layers.overlay,
        else => unreachable,
    };
}

fn handleDestroy(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const output: *hwc.desktop.Output = @fieldParentPtr("destroy", listener);

    for ([_]zwlr.LayerShellV1.Layer{ .overlay, .top, .bottom, .background }) |layer| {
        const tree = output.layerSurfaceTree(layer);
        tree.node.destroy();
    }

    server.output_manager.wlr_output_layout.remove(wlr_output);

    output.destroy.link.remove();
    output.frame.link.remove();
    output.request_state.link.remove();
    output.link.remove();

    server.allocator.destroy(output);

    log.info("{s}: name='{s}'", .{ @src().fn_name, wlr_output.name });
}

fn handleFrame(_: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const wlr_scene_output = server.wlr_scene.getSceneOutput(wlr_output).?;

    _ = blk: {
        if (!wlr_output.needs_frame and !wlr_scene_output.pending_commit_damage.notEmpty()) {
            break :blk;
        }

        var state = wlr.Output.State.init();
        defer state.finish();

        {
            const build_state_succussful = wlr_scene_output.buildState(&state, null);
            if (!build_state_succussful) {
                break :blk error.CommitFailed;
            }
        }

        {
            const commit_succussful = wlr_output.commitState(&state);
            if (!commit_succussful) {
                break :blk error.CommitFailed;
            }
        }
    } catch |err| {
        log.err("{s} failed: '{}': name='{s}'", .{ @src().fn_name, err, wlr_output.name });
    };

    var now: posix.timespec = undefined;
    posix.clock_gettime(posix.CLOCK.MONOTONIC, &now) catch @panic("CLOCK_MONOTONIC not supported");
    wlr_scene_output.sendFrameDone(&now);
}

fn handleRequestState(
    _: *wl.Listener(*wlr.Output.event.RequestState),
    event: *wlr.Output.event.RequestState,
) void {
    const successful_commit = event.output.commitState(event.state);

    log.info("{s}: {s} modeset: name='{s}'", .{
        @src().fn_name,
        if (successful_commit) "successful" else "failed",
        event.output.name,
    });
}
