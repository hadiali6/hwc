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
    outputs: wl.list.Head(Output, .link),

    /// The configuration that is currently being applied.
    pending_config: ?*wlr.OutputConfigurationV1 = null,

    /// The outputs that are currently being configured. This can be positive even
    /// if pending_config is zero when a failed configuration is being cancelled.
    pending_outputs: u32 = 0,

    apply_config: wl.Listener(*wlr.OutputConfigurationV1) =
        wl.Listener(*wlr.OutputConfigurationV1).init(handleApply),
    test_config: wl.Listener(*wlr.OutputConfigurationV1) =
        wl.Listener(*wlr.OutputConfigurationV1).init(handleTest),
    destroy: wl.Listener(*wlr.OutputManagerV1) =
        wl.Listener(*wlr.OutputManagerV1).init(handleDestroy),

    pub fn init(self: *OutputManager) !void {
        self.* = .{
            .manager = try wlr.OutputManagerV1.create(server.wl_server),
            .outputs = undefined,
        };
        self.outputs.init();
        self.manager.events.apply.add(&self.apply_config);
        self.manager.events.@"test".add(&self.test_config);
        self.manager.events.destroy.add(&self.destroy);
    }

    /// Send the current output configuration to clients.
    pub fn sendConfig(self: *OutputManager) !void {
        std.debug.assert(self.pending_config == null);

        const config = wlr.OutputConfigurationV1.create() catch {
            return error.ConfigCreateOOM;
        };
        errdefer config.destroy();

        var iterator = self.outputs.iterator(.forward);
        while (iterator.next()) |output| {
            _ = output.createHead(config) catch {
                return error.ConfigHeadCreateOOM;
            };
        }
        self.manager.setConfiguration(config);
    }

    /// Finish a configuration and send the new state to clients if it was succesful.
    pub fn finishConfiguration(self: *OutputManager) void {
        std.debug.assert(self.pending_outputs == 0);
        log.info("Configuration succeeded", .{});

        var iterator = self.outputs.iterator(.forward);
        while (iterator.next()) |output| {
            output.previous_config = null;
            output.pending_config = null;
        }

        if (self.pending_config) |pending_config| {
            pending_config.sendSucceeded();
            self.pending_config = null;
            self.sendConfig() catch |err| switch (err) {
                error.ConfigCreateOOM => log.err("failed to allocate output configuration {}", .{err}),
                error.ConfigHeadCreateOOM => log.err("failed to allocate output configuration head {}", .{err}),
            };
        }
    }

    /// Cancel a failed configuration.
    pub fn cancelConfiguration(self: *OutputManager) void {
        log.info("cancelling failed configuration", .{});

        if (self.pending_config == null) {
            if (self.pending_outputs != 0) {
                log.warn("tried to cancel a cancellation. stopping at current state", .{});

                var iterator = self.outputs.iterator(.forward);
                while (iterator.next()) |output| {
                    output.previous_config = null;
                    output.pending_config = null;
                }

                self.sendConfig() catch |err| switch (err) {
                    error.ConfigCreateOOM => log.err("failed to allocate output configuration {}", .{err}),
                    error.ConfigHeadCreateOOM => log.err("failed to allocate output configuration head {}", .{err}),
                };

                return;
            }
            return;
        }

        const pending = self.pending_config.?;
        self.pending_outputs = 0;

        var iterator = pending.heads.iterator(.forward);
        while (iterator.next()) |head| {
            const output: *Output = @ptrFromInt(head.state.output.data);

            if (output.pending_config != null) {
                output.pending_config = null;
            }

            if (output.previous_config != null) {
                output.pending_config = output.previous_config;
                output.previous_config = null;
                self.pending_outputs += 1;
            }
        }

        pending.sendFailed();
        pending.destroy();
        self.pending_config = null;
    }

    /// Add a new output.
    pub fn addOutput(self: *OutputManager, output: *Output) void {
        self.outputs.append(output);

        // Keep things simple and don't allow modifying the pending configuration.
        // Just cancel everything and let the client retry. This won't work very
        // well if a failed configuration is currently being cancelled, but that's
        // fine; we needn't handle all possible special cases.
        if (self.pending_config != null) {
            self.cancelConfiguration();
        }
        self.sendConfig() catch |err| switch (err) {
            error.ConfigCreateOOM => log.err("failed to allocate output configuration {}", .{err}),
            error.ConfigHeadCreateOOM => log.err("failed to allocate output configuration head {}", .{err}),
        };
    }

    fn handleApply(
        listener: *wl.Listener(*wlr.OutputConfigurationV1),
        configuration: *wlr.OutputConfigurationV1,
    ) void {
        const manager: *OutputManager = @fieldParentPtr("apply_config", listener);

        if (manager.pending_config != null or manager.pending_outputs != 0) {
            log.warn("Unable to apply configuration: previous one in progress", .{});
            configuration.sendFailed();
            configuration.destroy();
            return;
        }

        manager.pending_config = configuration;
        var iterator = configuration.heads.iterator(.forward);
        while (iterator.next()) |head| {
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

    fn handleTest(
        _: *wl.Listener(*wlr.OutputConfigurationV1),
        configuration: *wlr.OutputConfigurationV1,
    ) void {
        var failed = false;
        var iterator = configuration.heads.iterator(.forward);

        while (iterator.next()) |head| {
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

    fn handleDestroy(
        listener: *wl.Listener(*wlr.OutputManagerV1),
        _: *wlr.OutputManagerV1,
    ) void {
        const manager: *OutputManager = @fieldParentPtr("destroy", listener);

        manager.apply_config.link.remove();
        manager.test_config.link.remove();
        manager.destroy.link.remove();
    }
};
