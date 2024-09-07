const std = @import("std");
const wlr = @import("wlroots");

const Server = @import("Server.zig").Server;

const log = std.log.scoped(.main);
const gpa = std.heap.c_allocator;

const ArgsError = error{
    InvalidVerbosityLevel,
    InvalidConfigPath,
    InvalidArgs,
};

const Exit = enum(u1) {
    success = 0,
    failure = 1,
};

const ArgCase = enum {
    @"-c",
    @"--config",
    @"-h",
    @"--help",
    @"-s",
    @"--startup",
    @"-v",
    @"--version",
    @"-V",
    @"--verbosity",
    none,
};

const hwc_version = "0.01-alpha";
const default_hwc_config_path = "~/.config/hwc/config";
const help_message =
    \\Usage: {s} [options]
    \\Options:
    \\-v --version                      Display version.
    \\-V --verbosity <level>            Set verbosity level. 0 = silent, 1 = error, 2 = info, 3 = debug.
    \\-h --help                         Display this help message.
    \\-c --config <path-to-config-file> Specify a config file.
    \\-s --startup <command>            Specify a command to run at startup.
    \\
;

pub var server: Server = undefined;

const FlagHandler = struct {
    fn wrong(binary: []const u8) void {
        std.debug.print(help_message, .{binary});
        std.process.exit(@intFromEnum(Exit.failure));
    }

    fn help(binary: []const u8) void {
        std.debug.print(help_message, .{binary});
        std.process.exit(@intFromEnum(Exit.success));
    }

    fn version() void {
        std.debug.print(".{s}\n", .{hwc_version});
        std.process.exit(@intFromEnum(Exit.success));
    }

    fn config(args: *std.process.ArgIterator) ArgsError!void {
        const next_arg = args.next() orelse "-";
        if (std.mem.startsWith(u8, next_arg, "-")) {
            return ArgsError.InvalidArgs;
        }
        log.info("Config path set to {s}", .{next_arg});
    }

    fn startup(
        args: *std.process.ArgIterator,
        cmd: *[]const u8,
    ) ArgsError!void {
        const next_arg = args.next() orelse "-";
        if (std.mem.startsWith(u8, next_arg, "-")) {
            return ArgsError.InvalidArgs;
        }
        log.info("Startup command set to {s}", .{next_arg});
        cmd.* = next_arg;
    }

    fn verbosity(
        args: *std.process.ArgIterator,
        verbosity_value: *wlr.log.Importance,
    ) ArgsError!void {
        const next_arg = args.next() orelse "-";
        if (std.mem.startsWith(u8, next_arg, "-")) {
            return ArgsError.InvalidArgs;
        }
        const level = std.fmt.parseInt(u8, next_arg, 10) catch {
            log.err(
                "Failed to parse verbosity level! Setting verbosity to {d}",
                .{@intFromEnum(verbosity_value.*)},
            );
            return;
        };
        switch (level) {
            0 => verbosity_value.* = wlr.log.Importance.silent,
            1 => verbosity_value.* = wlr.log.Importance.err,
            2 => verbosity_value.* = wlr.log.Importance.info,
            3 => verbosity_value.* = wlr.log.Importance.debug,
            else => return ArgsError.InvalidVerbosityLevel,
        }
        log.info("Wlr Log Verbosity set to {d}", .{@intFromEnum(verbosity_value.*)});
    }
};

pub fn main() anyerror!void {
    var verbosity: wlr.log.Importance = .silent;
    var cmd: []const u8 = undefined;

    var args = std.process.args();
    const binary_path = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--") or std.mem.startsWith(u8, arg, "-")) {
            const flag = std.meta.stringToEnum(ArgCase, arg[0..]);
            switch (flag orelse ArgCase.none) {
                .@"-h", .@"--help" => FlagHandler.help(binary_path.?),
                .@"-v", .@"--version" => FlagHandler.version(),
                .@"-c", .@"--config" => try FlagHandler.config(&args),
                .@"-s", .@"--startup" => try FlagHandler.startup(&args, &cmd),
                .@"-V", .@"--verbosity" => try FlagHandler.verbosity(&args, &verbosity),
                else => FlagHandler.wrong(binary_path.?),
            }
        }
    }

    wlr.log.init(verbosity, null);

    try server.init();
    defer server.deinit();

    const socket = apply_socket: {
        var buf: [11]u8 = undefined;
        break :apply_socket try server.wl_server.addSocketAuto(&buf);
    };

    if (std.os.argv.len >= 2) {
        var child = std.process.Child.init(
            &[_][]const u8{ "/bin/sh", "-c", cmd },
            gpa,
        );
        var env_map = try std.process.getEnvMap(gpa);
        defer env_map.deinit();
        try env_map.put("WAYLAND_DISPLAY", socket);
        child.env_map = &env_map;
        try child.spawn();
    }

    try server.backend.start();

    log.info("Running compositor on WAYLAND_DISPLAY={s}\n", .{socket});
    server.wl_server.run();
}
