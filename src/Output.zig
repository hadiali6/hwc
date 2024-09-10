const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const util = @import("util.zig");

const server = &@import("main.zig").server;

const log = std.log.scoped(.output);

pub const Output = struct {
    wlr_output: *wlr.Output,

    frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(frame),
    request_state: wl.Listener(*wlr.Output.event.RequestState) =
        wl.Listener(*wlr.Output.event.RequestState).init(requestState),
    destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(destroy),

    // The wlr.Output should be destroyed by the caller on failure to trigger cleanup.
    pub fn create(wlr_output: *wlr.Output) !void {
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

        const output = try util.gpa.create(Output);

        output.* = .{
            .wlr_output = wlr_output,
        };

        wlr_output.data = @intFromPtr(output);

        wlr_output.events.frame.add(&output.frame);
        wlr_output.events.request_state.add(&output.request_state);
        wlr_output.events.destroy.add(&output.destroy);

        const layout_output = try server.output_layout.addAuto(wlr_output);

        const scene_output = try server.scene.createSceneOutput(wlr_output);
        server.scene_output_layout.addOutput(layout_output, scene_output);
    }

    fn frame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("frame", listener);

        const scene_output = server.scene.getSceneOutput(output.wlr_output).?;
        _ = scene_output.commit(null);

        var now: std.posix.timespec = undefined;
        std.posix.clock_gettime(std.posix.CLOCK.MONOTONIC, &now) catch {
            @panic("CLOCK_MONOTONIC not supported");
        };
        scene_output.sendFrameDone(&now);
    }

    fn requestState(
        listener: *wl.Listener(*wlr.Output.event.RequestState),
        event: *wlr.Output.event.RequestState,
    ) void {
        const output: *Output = @fieldParentPtr("request_state", listener);
        _ = output.wlr_output.commitState(event.state);
    }

    fn destroy(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
        const output: *Output = @fieldParentPtr("destroy", listener);

        output.frame.link.remove();
        output.destroy.link.remove();

        util.gpa.destroy(output);
    }
};
