const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");

const Output = @import("Output.zig").Output;

const server = &@import("main.zig").server;

const log = std.log.scoped(.output_manager);

pub const OutputManager = struct {
    manager: *wlr.OutputManagerV1,
    /// All the outputs known to the manager.
    outputs: std.DoublyLinkedList(Output) = .{},
    /// The configuration that is currently being applied.
    pending_config: ?*wlr.OutputConfigurationV1 = null,
    /// The outputs that are currently being configured. This can be positive even
    /// if pending_config is zero when a failed configuration is being cancelled.
    pending_outputs: u32 = 0,

    apply: wl.Listener(*wlr.OutputConfigurationV1) = wl.Listener(*wlr.OutputConfigurationV1).init(apply),
    test_config: wl.Listener(*wlr.OutputConfigurationV1) = wl.Listener(*wlr.OutputConfigurationV1).init(testConfig),
    destroy: wl.Listener(*wlr.OutputManagerV1) = wl.Listener(*wlr.OutputManagerV1).init(destroy),

    pub fn init(manager: *OutputManager) !void {
        manager.* = .{
            .manager = try wlr.OutputManagerV1.create(server.wl_server),
        };
        manager.manager.events.apply.add(&manager.apply);
        manager.manager.events.@"test".add(&manager.test_config);
        manager.manager.events.destroy.add(&manager.destroy);
    }

    /// Send the current output configuration to clients.
    pub fn sendConfig(manager: *const OutputManager) !void {
        std.debug.assert(manager.pending_config == null);

        const config = try wlr.OutputConfigurationV1.create();
        errdefer config.destroy();

        var it = manager.outputs.first;
        while (it) |output_node| : (it = output_node.next) {
            _ = try output_node.data.createHead(config);
        }
        manager.manager.setConfiguration(config);
    }

    /// Finish a configuration and send the new state to clients if it was
    /// succesful.
    pub fn finishConfiguration(manager: *OutputManager) void {
        std.debug.assert(manager.pending_outputs == 0);
        log.info("Configuration succeeded", .{});
        var it = manager.outputs.first;
        while (it) |output_node| : (it = output_node.next) {
            output_node.data.previous_config = null;
            output_node.data.pending_config = null;
        }
        if (manager.pending_config) |pending_config| {
            pending_config.sendSucceeded();
            manager.pending_config = null;
            manager.sendConfig() catch {};
        }
    }

    /// Cancel a failed configuration.
    pub fn cancelConfiguration(manager: *OutputManager) void {
        log.info("Cancelling failed configuration", .{});
        if (manager.pending_config == null) {
            if (manager.pending_outputs != 0) {
                log.warn("Tried to cancel a cancellation. Stopping at current state", .{});
                var it = manager.outputs.first;
                while (it) |output| : (it = output.next) {
                    output.data.previous_config = null;
                    output.data.pending_config = null;
                }
                manager.sendConfig() catch {
                    log.err("Failed to send current output state", .{});
                };
                return;
            }
            return;
        }
        const pending = manager.pending_config.?;
        manager.pending_outputs = 0;

        var it = pending.heads.iterator(.forward);
        while (it.next()) |head| {
            const output: *Output = @ptrFromInt(head.state.output.data);
            if (output.pending_config != null) {
                output.pending_config = null;
            }
            if (output.previous_config != null) {
                output.pending_config = output.previous_config;
                output.previous_config = null;
                manager.pending_outputs += 1;
            }
        }
        pending.sendFailed();
        pending.destroy();
        manager.pending_config = null;
    }

    /// Add a new output.
    pub fn addOutput(manager: *OutputManager, wlr_output: *wlr.Output) !void {
        const node = try Output.create(wlr_output);
        manager.outputs.append(node);

        // Keep things simple and don't allow modifying the pending configuration.
        // Just cancel everything and let the client retry. This won't work very
        // well if a failed configuration is currently being cancelled, but that's
        // fine; we needn't handle all possible special cases.
        if (manager.pending_config != null) {
            manager.cancelConfiguration();
        }
        try manager.sendConfig();
    }

    fn apply(listener: *wl.Listener(*wlr.OutputConfigurationV1), configuration: *wlr.OutputConfigurationV1) void {
        const manager: *OutputManager = @fieldParentPtr("apply", listener);
        if (manager.pending_config != null or manager.pending_outputs != 0) {
            log.warn("Unable to apply configuration: previous one in progress", .{});
            configuration.sendFailed();
            configuration.destroy();
            return;
        }
        manager.pending_config = configuration;
        var it = configuration.heads.iterator(.forward);
        while (it.next()) |head| {
            const output: *Output = @ptrFromInt(head.state.output.data);
            std.debug.assert(output.previous_config == null);
            std.debug.assert(output.pending_config == null);
            if (head.state.enabled and !output.wlr_output.enabled) {
                output.commitConfig(&head.state) catch {
                    manager.cancelConfiguration();
                    return;
                };
            } else {
                // We could test the config before trying to commit it, but it is
                // not done to give the commit error handling code more testing.
                output.pending_config = head.state;
                manager.pending_outputs += 1;
                output.wlr_output.scheduleFrame();
            }
        }
    }

    fn testConfig(listener: *wl.Listener(*wlr.OutputConfigurationV1), configuration: *wlr.OutputConfigurationV1) void {
        _ = listener;
        var it = configuration.heads.iterator(.forward);
        var failed = false;
        while (it.next()) |head| {
            var output_state = wlr.Output.State.init();
            defer output_state.finish();
            head.state.apply(&output_state);
            if (!head.state.output.testState(&output_state)) {
                failed = true;
                break;
            }
        }
        if (failed) {
            configuration.sendFailed();
        } else {
            configuration.sendSucceeded();
        }
        configuration.destroy();
    }

    fn destroy(listener: *wl.Listener(*wlr.OutputManagerV1), _: *wlr.OutputManagerV1) void {
        const manager: *OutputManager = @fieldParentPtr("destroy", listener);
        manager.apply.link.remove();
        manager.test_config.link.remove();
        manager.destroy.link.remove();
    }
};
