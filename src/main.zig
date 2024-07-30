const std = @import("std");
const Server = @import("server.zig").Server;

const wlr = @import("wlroots");

const version = "0.01-alpha";
const default_hwc_config_path = "~/.config/hwc/config";

const ArgsError = error{
    InvalidVerbosityLevel,
    InvalidConfigPath,
    InvalidArgs,
};

const gpa = std.heap.c_allocator;

const Exit = enum(u1) {
    success = 0,
    failure = 1,
};

const LongArgCase = enum {
    help,
    config,
    startup,
    version,
    verbosity,
    none,
};

const ShortArgCase = enum { h, c, s, v, V, none };

const help =
    \\Usage: {s} [options]
    \\Options:
    \\-v --version                      Display version.
    \\-V --verbosity <level>            Set verbosity level. 0 = silent, 1 = error, 2 = info, 3 = debug.
    \\-h --help                         Display this help message.
    \\-c --config <path-to-config-file> Specify a config file.
    \\-s --startup <command>            Specify a command to run at startup.
    \\
;

pub fn main() anyerror!void {
    var verbosity: wlr.log.Importance = .silent;
    var cmd: []const u8 = undefined;

    var args = std.process.args();
    const binary = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            const flag = std.meta.stringToEnum(LongArgCase, arg[2..]);
            switch (flag orelse LongArgCase.none) {
                .help => handleHelpFlag(binary.?),
                .version => handleVersionFlag(),
                .config => try handleConfigFlag(&args, arg),
                .startup => try handleStartupFlag(&args, arg, &cmd),
                .verbosity => try handleVerbosityFlag(&args, arg, &verbosity),
                else => handleWrongFlag(binary.?),
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            const flag = std.meta.stringToEnum(ShortArgCase, arg[1..]);
            switch (flag orelse ShortArgCase.none) {
                .h => handleHelpFlag(binary.?),
                .v => handleVersionFlag(),
                .c => try handleConfigFlag(&args, arg),
                .s => try handleStartupFlag(&args, arg, &cmd),
                .V => try handleVerbosityFlag(&args, arg, &verbosity),
                else => handleWrongFlag(binary.?),
            }
        }
    }

    wlr.log.init(verbosity, null);

    var server: Server = undefined;
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

    std.log.info("Running compositor on WAYLAND_DISPLAY={s}\n", .{socket});
    server.wl_server.run();
}

fn handleWrongFlag(binary: []const u8) void {
    std.debug.print(help, .{binary});
    std.process.exit(@intFromEnum(Exit.failure));
}

fn handleHelpFlag(binary: []const u8) void {
    std.debug.print(help, .{binary});
    std.process.exit(@intFromEnum(Exit.success));
}

fn handleVersionFlag() void {
    std.debug.print(".{s}\n", .{version});
    std.process.exit(@intFromEnum(Exit.success));
}

fn handleConfigFlag(
    args: *std.process.ArgIterator,
    arg: []const u8,
) ArgsError!void {
    const next_arg = args.next() orelse "--";
    if (!std.mem.startsWith(u8, arg, "--")) {
        return ArgsError.InvalidArgs;
    }
    std.log.info("Config path set to {s}", .{next_arg});
}

fn handleStartupFlag(
    args: *std.process.ArgIterator,
    arg: []const u8,
    cmd: *[]const u8,
) ArgsError!void {
    const next_arg = args.next() orelse "--";
    if (!std.mem.startsWith(u8, arg, "--")) {
        return ArgsError.InvalidArgs;
    }
    std.log.info("Startup command set to {s}", .{next_arg});
    cmd.* = next_arg;
}

fn handleVerbosityFlag(
    args: *std.process.ArgIterator,
    arg: []const u8,
    verbosity: *wlr.log.Importance,
) ArgsError!void {
    const next_arg = args.next() orelse "--";
    if (!std.mem.startsWith(u8, arg, "--")) {
        return ArgsError.InvalidArgs;
    }
    const level = std.fmt.parseInt(u8, next_arg, 10) catch {
        std.log.err(
            "Failed to parse verbosity level! Setting verbosity to {d}",
            .{@intFromEnum(verbosity.*)},
        );
        return;
    };
    switch (level) {
        0 => verbosity.* = wlr.log.Importance.silent,
        1 => verbosity.* = wlr.log.Importance.err,
        2 => verbosity.* = wlr.log.Importance.info,
        3 => verbosity.* = wlr.log.Importance.debug,
        else => return ArgsError.InvalidVerbosityLevel,
    }
    std.log.info("Wlr Log Verbosity set to {d}", .{@intFromEnum(verbosity.*)});
}
