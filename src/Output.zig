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
        const output = try util.gpa.create(Output);

        output.* = .{
            .wlr_output = wlr_output,
        };
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
