const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const log = std.log.scoped(.lua);
const mem = std.mem;
const posix = std.posix;

const ziglua = @import("ziglua");

const hwc = @import("hwc.zig");
const util = @import("util.zig");
const api = @import("api.zig");

const server = &@import("root").server;

const Allocator = std.mem.Allocator;
const Lua = ziglua.Lua;

pub fn init() !*Lua {
    var lua = try Lua.init(util.allocator);

    lua.openLibs();

    lua.registerFns("hwc", &[_]ziglua.FnReg{
        .{ .name = "spawn", .func = ziglua.wrap(spawn) },
        .{ .name = "exit", .func = ziglua.wrap(exit) },
        .{ .name = "reload", .func = ziglua.wrap(reload) },
        .{ .name = "add_keybind", .func = ziglua.wrap(addKeybind) },
        .{ .name = "remove_keybind", .func = ziglua.wrap(removeKeybind) },
        .{ .name = "remove_keybind_by_id", .func = ziglua.wrap(removeKeybindById) },
    });

    try setPackagePath(lua, util.allocator);

    return lua;
}

pub fn runScript(lua: *Lua) !void {
    const path = getConfigPath(util.allocator) catch |err| switch (err) {
        error.OutOfMemory => {
            log.err("Failed to allocate config path.", .{});
            return err;
        },
        error.NoConfigFile => {
            log.err("No configuration file found under $XDG_CONFIG_HOME/hwc/hwc.lua or $HOME/hwc/hwc.lua", .{});
            return err;
        },
    };
    defer util.allocator.free(path);

    lua.doFile(path) catch |err| {
        log.err("{s}", .{try lua.toString(-1)});
        lua.pop(1);
        return err;
    };
}

pub fn runString(lua: *Lua, str: [:0]const u8) !void {
    try lua.doString(str);
}

fn setPackagePath(lua: *Lua, allocator: Allocator) !void {
    _ = try lua.getGlobal("package");
    _ = lua.getField(-1, "path");

    const current_path = try lua.toString(-1);

    const new_path: []const u8 = get_new_path: {
        if (posix.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
            break :get_new_path try fmt.allocPrint(
                allocator,
                "{s};{s}/hwc/?.lua;{s}/hwc/?/init.lua",
                .{ current_path, xdg_config_home, xdg_config_home },
            );
        } else if (posix.getenv("HOME")) |home| {
            break :get_new_path try fmt.allocPrint(
                allocator,
                "{s};{s}/.config/hwc/?.lua;{s}/.config/hwc/?/init.lua",
                .{ current_path, home, home },
            );
        } else {
            return error.NoPath;
        }
    };
    defer allocator.free(new_path);

    _ = lua.pushString(new_path);
    lua.setField(-3, "path");
    lua.pop(1);
}

fn getConfigPath(allocator: Allocator) ![:0]const u8 {
    return get_config_path: {
        if (posix.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
            break :get_config_path try fs.path.joinZ(
                allocator,
                &[_][]const u8{ xdg_config_home, "hwc/hwc.lua" },
            );
        } else if (posix.getenv("HOME")) |home| {
            break :get_config_path try fs.path.joinZ(
                allocator,
                &[_][]const u8{ home, ".config/hwc/hwc.lua" },
            );
        } else {
            return error.NoConfigFile;
        }
    };
}

fn spawn(lua: *Lua) i32 {
    const cmd = get_cmd: {
        if (lua.isNoneOrNil(1)) {
            lua.raiseErrorStr("Spawn failed due to nil or no command argument.", .{});
            return 0;
        }
        if (!lua.isString(1) or lua.isNumber(1)) {
            lua.raiseErrorStr("Spawn failed due to incorrect type for command argument. " ++
                "Command must a string.", .{});
            return 0;
        }
        break :get_cmd lua.toString(1) catch unreachable;
    };

    const pid_requested = get_pid_requested: {
        if (lua.isNoneOrNil(2)) {
            break :get_pid_requested false;
        }
        if (!lua.isBoolean(2)) {
            lua.raiseErrorStr("Spawn failed due to incorrect type for request_pid argument. " ++
                "request_pid must be a boolean.", .{});
            return 0;
        }
        break :get_pid_requested lua.toBoolean(2);
    };

    const stdin_fd_requested = get_stdin_fd_requested: {
        if (lua.isNoneOrNil(3)) {
            break :get_stdin_fd_requested false;
        }
        if (!lua.isBoolean(3)) {
            lua.raiseErrorStr("Spawn failed due to incorrect type for request_stdin_fd argument. " ++
                "request_stdin_fd must be a boolean.", .{});
            return 0;
        }
        break :get_stdin_fd_requested lua.toBoolean(3);
    };

    const stdout_fd_requested = get_stdout_fd_requested: {
        if (lua.isNoneOrNil(4)) {
            break :get_stdout_fd_requested false;
        }
        if (!lua.isBoolean(4)) {
            lua.raiseErrorStr("Spawn failed due to incorrect type for request_stdout_fd argument. " ++
                "request_stdout_fd must be a boolean.", .{});
            return 0;
        }
        break :get_stdout_fd_requested lua.toBoolean(4);
    };

    const stderr_fd_requested = get_stderr_fd_requested: {
        if (lua.isNoneOrNil(5)) {
            break :get_stderr_fd_requested false;
        }
        if (!lua.isBoolean(5)) {
            lua.raiseErrorStr("Spawn failed due to incorrect type for request_stderr_fd argument. " ++
                "request_stderr_fd must be a boolean.", .{});
            return 0;
        }
        break :get_stderr_fd_requested lua.toBoolean(5);
    };

    if (stdin_fd_requested or stdout_fd_requested or stderr_fd_requested) {
        const info: api.ProcessResult = api.pipedSpawnWithStreams(cmd) catch |err| {
            log.debug("pipedSpawnWithStreams failed: {}", .{err});
            return 0;
        };
        log.debug("pid: {}, stdin_fd: {}, stdout_fd: {}, stderr_fd: {}", .{
            info.pid,
            info.stdin_fd,
            info.stdout_fd,
            info.stderr_fd,
        });
        lua.pushInteger(info.pid);
        lua.pushInteger(info.stdin_fd);
        lua.pushInteger(info.stdout_fd);
        lua.pushInteger(info.stderr_fd);
        return 4;
    }

    if (pid_requested) {
        const pid: i32 = api.pipedSpawn(cmd) catch |err| {
            log.debug("pipedSpawn failed: {}", .{err});
            return 0;
        };
        log.debug("pid: {}", .{pid});
        lua.pushInteger(pid);
        return 1;
    }

    api.spawn(cmd) catch |err| {
        log.debug("spawn failed: {}", .{err});
    };

    return 0;
}

fn exit(_: *Lua) i32 {
    server.wl_server.terminate();
    return 0;
}

fn reload(lua: *Lua) i32 {
    server.config.keybinds.clearAndFree(util.allocator);
    runScript(lua) catch unreachable;
    return 0;
}

fn addKeybind(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("key is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("modifiers is not a string", .{});
        return 0;
    }
    if (!lua.isBoolean(3)) {
        lua.raiseErrorStr("is_repeat is not a boolean", .{});
        return 0;
    }
    if (!lua.isBoolean(4)) {
        lua.raiseErrorStr("is_on_release is not a boolean", .{});
        return 0;
    }
    if (!lua.isNumber(5) and !lua.isNil(5)) {
        lua.raiseErrorStr("layout_index is not a integer", .{});
        return 0;
    }
    if (!lua.isFunction(6)) {
        lua.raiseErrorStr("callback is not a function", .{});
        return 0;
    }

    {
        const keysym = blk: {
            const key_str = lua.toString(1) catch unreachable;
            break :blk hwc.Keybind.parseKeysym(key_str) catch {
                lua.raiseErrorStr("unable to parse key", .{});
                return 0;
            };
        };
        const modifiers = blk: {
            const modifiers_str = lua.toString(2) catch unreachable;
            break :blk hwc.Keybind.parseModifiers(modifiers_str) catch {
                lua.raiseErrorStr("unable to parse modifiers", .{});
                return 0;
            };
        };
        const is_repeat = lua.toBoolean(3);
        const is_on_release = lua.toBoolean(4);
        const layout_index = lua.toInteger(5) catch null;

        const keybind = hwc.Keybind{
            .keysym = keysym,
            .modifiers = modifiers,
            .id = @intCast(server.config.keybinds.items.len),
            .exec_on_release = is_on_release,
            .repeat = is_repeat,
            .layout_index = if (layout_index) |i| @intCast(i) else null,
        };

        // Repeating mappings borrow the Mapping directly. To prevent a possible
        // crash if the Mapping ArrayList is reallocated, stop any currently
        // repeating mappings.
        server.input_manager.seat.clearRepeatingMapping();
        server.config.keybinds.append(util.allocator, keybind) catch {
            lua.raiseErrorStr("allocation failed", .{});
            return 0;
        };
    }

    var keybind = &server.config.keybinds.items[server.config.keybinds.items.len - 1];

    // Remove the old reference if one exists
    if (keybind.lua_fn_reference != ziglua.ref_nil) {
        lua.unref(ziglua.registry_index, keybind.lua_fn_reference);
    }

    // Copy the function to the top of the stack
    lua.pushValue(6);
    // Store the function reference in the Lua registry and remove from the stack
    keybind.lua_fn_reference = lua.ref(ziglua.registry_index) catch unreachable;

    lua.pushInteger(@intCast(keybind.id));

    return 1;
}

fn removeKeybind(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("Key is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("Modifiers is not a string", .{});
        return 0;
    }

    var index: u32 = 0;
    const found_keybind: ?hwc.Keybind = blk: {
        const keysym = inner: {
            const keybind_str = lua.toString(1) catch unreachable;
            break :inner hwc.Keybind.parseKeysym(keybind_str) catch unreachable;
        };

        const modifiers = inner: {
            const modifiers_str = lua.toString(2) catch unreachable;
            break :inner hwc.Keybind.parseModifiers(modifiers_str) catch unreachable;
        };

        for (server.config.keybinds.items) |keybind| {
            if (keybind.keysym == keysym and
                std.meta.eql(keybind.modifiers, modifiers))
            {
                break :blk keybind;
            }
            index += 1;
        }
        break :blk null;
    };

    if (found_keybind == null) {
        lua.pushBoolean(false);
        return 1;
    }

    _ = server.config.keybinds.orderedRemove(index);

    lua.pushBoolean(false);
    return 1;
}

fn removeKeybindById(lua: *Lua) i32 {
    if (!lua.isNumber(1)) {
        lua.raiseErrorStr("Key is not a integer", .{});
        return 0;
    }

    const id = lua.toInteger(1) catch unreachable;
    for (server.config.keybinds.items, 0..) |keybind, index| {
        if (keybind.id == id) {
            _ = server.config.keybinds.orderedRemove(index);
            lua.pushBoolean(true);
            return 1;
        }
    }

    lua.pushBoolean(false);
    return 1;
}
