const build_options = @import("build_options");
const builtin = @import("builtin");
const std = @import("std");
const io = std.io;
const log = std.log.scoped(.main);
const mem = std.mem;
const posix = std.posix;

const wlr = @import("wlroots");
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

const api = @import("api.zig");
const util = @import("util.zig");
const hwc = @import("hwc.zig");
const lua = @import("lua.zig");
const cli = @import("cli.zig");

const help_message =
    \\Usage: {s} [options]
    \\Options:
    \\-v --version                      Display version.
    \\-V --verbosity <level>            Set verbosity level. error, warning, info, debug.
    \\-h --help                         Display this help message.
    \\-c --config <path-to-config-file> Specify a config file.
    \\-s --startup <command>            Specify a command to run at startup.
    \\
;

pub var server: hwc.Server = undefined;
pub var lua_state: *Lua = undefined;

/// Set the default log level based on the build mode.
var runtime_log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .info,
};
var wlr_log_level: wlr.log.Importance = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseFast, .ReleaseSmall => .silent,
};

pub fn main() !void {
    const cli_args_result = cli.parser([*:0]const u8, &.{
        .{ .name = "h", .kind = .boolean },
        .{ .name = "v", .kind = .boolean },
        .{ .name = "c", .kind = .arg },
        .{ .name = "s", .kind = .arg },
        .{ .name = "V", .kind = .arg },
    }).parse(std.os.argv[1..]) catch {
        try io.getStdErr().writeAll(help_message);
        posix.exit(1);
    };

    if (cli_args_result.flags.h) {
        try io.getStdOut().writeAll(help_message);
        posix.exit(0);
    }

    if (cli_args_result.args.len != 0) {
        log.err("unknown option '{s}'", .{cli_args_result.args[0]});
        try io.getStdErr().writeAll(help_message);
        posix.exit(1);
    }

    if (cli_args_result.flags.v) {
        try io.getStdOut().writeAll(build_options.version ++ "\n");
        posix.exit(0);
    }

    if (cli_args_result.flags.V) |level| {
        if (mem.eql(u8, level, "error")) {
            runtime_log_level = .err;
            wlr_log_level = .err;
        } else if (mem.eql(u8, level, "warning")) {
            runtime_log_level = .warn;
            wlr_log_level = .err;
        } else if (mem.eql(u8, level, "info")) {
            runtime_log_level = .info;
            wlr_log_level = .info;
        } else if (mem.eql(u8, level, "debug")) {
            runtime_log_level = .debug;
            wlr_log_level = .debug;
        } else {
            log.err("invalid log level '{s}'", .{level});
            try io.getStdErr().writeAll(help_message);
            posix.exit(1);
        }
    }

    if (cli_args_result.flags.c) |config_path| {
        log.info("setting config path to {s}", .{config_path});
    }

    api.processSetup();

    lua_state = try lua.init();
    defer lua.deinit(lua_state);

    wlr.log.init(wlr_log_level, null);

    try server.init();
    defer server.deinit();

    const socket = try server.start();

    if (cli_args_result.flags.s) |startup_cmd| {
        api.spawn(startup_cmd);
    }

    try lua.runScript(lua_state);

    log.info("Running compositor on WAYLAND_DISPLAY={s}\n", .{socket});
    server.wl_server.run();
}
