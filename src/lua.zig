const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const log = std.log.scoped(.lua);
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.server.wl;
const wlr = @import("wlroots");
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

    lua.pushFunction(ziglua.wrap(overrideType));
    lua.setGlobal("type");

    try lua.newMetatable("output_mt");
    lua.pushFunction(ziglua.wrap(Output.index_cb));
    lua.setField(-2, "__index");
    _ = lua.pushString("hwc.Output");
    lua.setField(-2, "hwc_type_name");
    lua.pushFunction(ziglua.wrap(Output.tostring_cb));
    lua.setField(-2, "__tostring");

    lua.registerFns("hwc", &[_]ziglua.FnReg{
        .{ .name = "spawn", .func = ziglua.wrap(spawn) },
        .{ .name = "exit", .func = ziglua.wrap(exit) },
        .{ .name = "reload", .func = ziglua.wrap(reload) },
        .{ .name = "add_keybind", .func = ziglua.wrap(addKeybind) },
        .{ .name = "remove_keybind", .func = ziglua.wrap(removeKeybind) },
        .{ .name = "remove_keybind_by_id", .func = ziglua.wrap(removeKeybindById) },
        .{ .name = "create_keyboard_group", .func = ziglua.wrap(createKeyboardGroup) },
        .{ .name = "destroy_keyboard_group", .func = ziglua.wrap(destroyKeyboardGroup) },
        .{ .name = "keyboard_group_add_keyboard", .func = ziglua.wrap(addKeyboardGroup) },
        .{ .name = "keyboard_group_remove_keyboard", .func = ziglua.wrap(removeKeyboardGroup) },
        .{ .name = "create_output", .func = ziglua.wrap(createOutput) },
    });

    _ = lua.pushString(if (server.backend.isDrm())
        "drm"
    else if (server.backend.isWl())
        "wayland"
    else if (server.backend.isX11())
        "x11"
    else if (server.backend.isHeadless())
        "headless"
    else if (server.backend.isMulti())
        "multi"
    else
        unreachable);
    lua.setField(-2, "backend");

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

fn overrideType(lua: *Lua) i32 {
    lua.checkAny(1);

    _ = lua.pushString(blk: {
        const lua_type = lua.typeOf(1);

        if (lua_type == .userdata) {
            lua.getMetatable(1) catch break :blk "userdata";

            if (lua.getField(-1, "hwc_type_name") == .string) {
                break :blk lua.toString(-1) catch unreachable;
            } else break :blk "userdata";
        }

        break :blk lua.typeName(lua_type);
    });

    return 1;
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
            break :blk hwc.input.Keybind.parseKeysym(key_str) catch {
                lua.raiseErrorStr("unable to parse key", .{});
                return 0;
            };
        };
        const modifiers = blk: {
            const modifiers_str = lua.toString(2) catch unreachable;
            break :blk hwc.input.Keybind.parseModifiers(modifiers_str) catch {
                lua.raiseErrorStr("unable to parse modifiers", .{});
                return 0;
            };
        };
        const is_repeat = lua.toBoolean(3);
        const is_on_release = lua.toBoolean(4);
        const layout_index = lua.toInteger(5) catch null;

        const keybind = hwc.input.Keybind{
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
        server.input_manager.defaultSeat().clearRepeatingMapping();
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
    const found_keybind: ?hwc.input.Keybind = blk: {
        const keysym = inner: {
            const keybind_str = lua.toString(1) catch unreachable;
            break :inner hwc.input.Keybind.parseKeysym(keybind_str) catch unreachable;
        };

        const modifiers = inner: {
            const modifiers_str = lua.toString(2) catch unreachable;
            break :inner hwc.input.Keybind.parseModifiers(modifiers_str) catch unreachable;
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

// TODO: hwc.Seat type as userdata w/ metatable for methods
// (will do after merging input branch)

// TODO: hwc.KeyboardGroup type as userdata w/ metatable for methods
// (will do after merging input branch)
// :add_keyboard(device_identifier)
// :remove_keyboard(device_identifier)
// destroy() on __gc
fn createKeyboardGroup(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("seat identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("keyboard group identifier is not a string", .{});
        return 0;
    }

    const seat_id = lua.toString(1) catch unreachable;
    const keyboard_group_id = lua.toString(2) catch unreachable;

    const seat = api.findSeat(seat_id) orelse {
        lua.raiseErrorStr("no seat named %s", .{mem.sliceTo(seat_id, 0).ptr});
        return;
    };

    const keyboard_group = api.createKeyboardGroup() catch {
        lua.raiseErrorStr("keyboard group failed to allocate", .{});
        return 0;
    };

    keyboard_group.init(seat, keyboard_group_id) catch {
        lua.raiseErrorStr("keyboard group failed to init", .{});
        return 0;
    };

    return 0;
}

fn destroyKeyboardGroup(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("seat identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("keyboard group identifier is not a string", .{});
        return 0;
    }

    const seat_id = lua.toString(1) catch unreachable;
    const seat = api.findSeat(seat_id) orelse {
        lua.raiseErrorStr("no seat named %s", .{mem.sliceTo(seat_id, 0).ptr});
        return;
    };

    const keyboard_group_id = lua.toString(2) catch unreachable;
    const keyboard_group = api.findKeyboardGroup(seat, keyboard_group_id) orelse {
        lua.raiseErrorStr("no keyboard group named %s", .{mem.sliceTo(keyboard_group_id, 0).ptr});
        return;
    };

    keyboard_group.deinit();

    return 0;
}

fn addKeyboardGroup(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("seat identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("keyboard group identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(3)) {
        lua.raiseErrorStr("keyboard device identifier is not a string", .{});
        return 0;
    }

    const seat_id = lua.toString(1) catch unreachable;
    const seat = api.findSeat(seat_id) orelse {
        lua.raiseErrorStr("no seat named %s", .{mem.sliceTo(seat_id, 0).ptr});
        return;
    };

    const keyboard_group_id = lua.toString(2) catch unreachable;
    const keyboard_group = api.findKeyboardGroup(seat, keyboard_group_id) orelse {
        lua.raiseErrorStr("no keyboard group named %s", .{mem.sliceTo(keyboard_group_id, 0).ptr});
        return;
    };

    const keyboard_device_id = lua.toString(3) catch unreachable;
    keyboard_group.addKeyboard(keyboard_device_id) catch {
        lua.raiseErrorStr("failed to add %s to %s", .{
            mem.sliceTo(keyboard_device_id, 0).ptr,
            mem.sliceTo(keyboard_group_id, 0).ptr,
        });
        return;
    };

    return 0;
}

fn removeKeyboardGroup(lua: *Lua) i32 {
    if (!lua.isString(1)) {
        lua.raiseErrorStr("seat identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(2)) {
        lua.raiseErrorStr("keyboard group identifier is not a string", .{});
        return 0;
    }
    if (!lua.isString(3)) {
        lua.raiseErrorStr("keyboard device identifier is not a string", .{});
        return 0;
    }

    const seat_id = lua.toString(1) catch unreachable;
    const seat = api.findSeat(seat_id) orelse {
        lua.raiseErrorStr("no seat named %s", .{mem.sliceTo(seat_id, 0).ptr});
        return;
    };

    const keyboard_group_id = lua.toString(2) catch unreachable;
    const keyboard_group = api.findKeyboardGroup(seat, keyboard_group_id) orelse {
        lua.raiseErrorStr("no keyboard group named %s", .{mem.sliceTo(keyboard_group_id, 0).ptr});
        return;
    };

    keyboard_group.removeKeyboard(lua.toString(3) catch unreachable);

    return 0;
}

const Output = struct {
    name: [*:0]u8,
    make: ?[*:0]u8,
    model: ?[*:0]u8,
    serial: ?[*:0]u8,
    description: ?[*:0]u8,
    backend: enum { drm, wayland, x11, headless },
    width: i32,
    height: i32,
    refresh: i32,
    scale: f32,
    enabled: bool,
    adaptive_sync_supported: bool,
    adaptive_sync_enabled: bool,
    transform: wl.Output.Transform,

    fn init(self: *Output, wlr_output: *wlr.Output) void {
        self.name = wlr_output.name;
        self.make = wlr_output.make;
        self.model = wlr_output.model;
        self.serial = wlr_output.serial;
        self.description = wlr_output.description;

        self.backend = if (wlr_output.isDrm())
            .drm
        else if (wlr_output.isWl())
            .wayland
        else if (wlr_output.isX11())
            .x11
        else if (wlr_output.isHeadless())
            .headless
        else
            unreachable;

        self.width = wlr_output.width;
        self.height = wlr_output.height;
        self.refresh = wlr_output.refresh;
        self.scale = wlr_output.scale;
        self.enabled = wlr_output.enabled;
        self.adaptive_sync_supported = wlr_output.adaptive_sync_supported;
        self.adaptive_sync_enabled = switch (wlr_output.adaptive_sync_status) {
            .enabled => true,
            .disabled => false,
        };
        self.transform = wlr_output.transform;
    }

    fn pushField(self: *Output, lua: *Lua, field: [:0]const u8) void {
        if (mem.eql(u8, field, "name")) {
            _ = lua.pushString(self.name[0..mem.len(self.name)]);
        } else if (mem.eql(u8, field, "make")) {
            if (self.make) |make| {
                _ = lua.pushString(self.name[0..mem.len(make)]);
            } else {
                lua.pushNil();
            }
        } else if (mem.eql(u8, field, "model")) {
            if (self.make) |model| {
                _ = lua.pushString(self.name[0..mem.len(model)]);
            } else {
                lua.pushNil();
            }
        } else if (mem.eql(u8, field, "description")) {
            if (self.description) |description| {
                _ = lua.pushString(self.name[0..mem.len(description)]);
            } else {
                lua.pushNil();
            }
        } else if (mem.eql(u8, field, "serial")) {
            if (self.serial) |serial| {
                _ = lua.pushString(self.name[0..mem.len(serial)]);
            } else {
                lua.pushNil();
            }
        } else if (mem.eql(u8, field, "backend")) {
            _ = lua.pushString(@tagName(self.backend));
        } else if (mem.eql(u8, field, "width")) {
            lua.pushInteger(@intCast(self.width));
        } else if (mem.eql(u8, field, "height")) {
            lua.pushInteger(@intCast(self.height));
        } else if (mem.eql(u8, field, "refresh")) {
            lua.pushInteger(@intCast(self.refresh));
        } else if (mem.eql(u8, field, "scale")) {
            lua.pushNumber(@floatCast(self.scale));
        } else if (mem.eql(u8, field, "enabled")) {
            lua.pushBoolean(self.enabled);
        } else if (mem.eql(u8, field, "adaptive_sync_supported")) {
            lua.pushBoolean(self.adaptive_sync_supported);
        } else if (mem.eql(u8, field, "adaptive_sync_status")) {
            lua.pushBoolean(self.adaptive_sync_enabled);
        } else if (mem.eql(u8, field, "transform")) {
            _ = lua.pushString(@tagName(self.transform));
        } else {
            lua.pushNil();
        }
    }

    fn index_cb(lua: *Lua) i32 {
        std.debug.assert(lua.isUserdata(-2));
        std.debug.assert(lua.isString(-1));

        const output: *Output = lua.toUserdata(Output, -2) catch unreachable;
        const index = lua.toString(-1) catch unreachable;
        output.pushField(lua, index);
        return 1;
    }

    fn tostring_cb(lua: *Lua) i32 {
        const output: *Output = lua.toUserdata(Output, -1) catch unreachable;
        _ = lua.pushFString("hwc.Output: %p", .{output});
        return 1;
    }
};

fn createOutput(lua: *Lua) i32 {
    if (!lua.isNumber(1) and !lua.isNoneOrNil(1)) {
        lua.raiseErrorStr("width is not a integer", .{});
        return 0;
    }
    if (!lua.isNumber(2) and !lua.isNoneOrNil(2)) {
        lua.raiseErrorStr("height is not a integer", .{});
        return 0;
    }

    const width = if (!lua.isNoneOrNil(1))
        lua.toInteger(1) catch unreachable
    else
        1920;

    const height = if (!lua.isNoneOrNil(2))
        lua.toInteger(2) catch unreachable
    else
        1080;

    if (width < 0 or height < 0) {
        lua.raiseErrorStr("height cannot be negative", .{});
        return 0;
    }

    const wlr_output = api.createOutput(@intCast(width), @intCast(height)) catch return 0;
    const output: *Output = lua.newUserdata(Output);
    output.init(wlr_output);

    _ = lua.getMetatableRegistry("output_mt");
    std.debug.assert(lua.isTable(-1));
    lua.setMetatable(-2);

    return 1;
}
