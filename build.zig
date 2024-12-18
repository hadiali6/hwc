const std = @import("std");
const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lua_version = std.meta.stringToEnum(
        enum {
            lua51,
            lua52,
            lua53,
            lua54,
            luajit,
            luau,
        },
        b.option([]const u8, "lua-version", "Choose lua version") orelse "none",
    ) orelse .lua51;

    switch (lua_version) {
        .lua51, .luajit => {},
        .lua52, .lua53, .lua54 => std.log.warn("lua 5.2, 5.3, and 5.4 may not work", .{}),
        .luau => {
            std.log.err("luau is not supported", .{});
            return;
        },
    }

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
        .shared = true,
        .lang = lua_version,
    }).module("ziglua");

    const scanner = Scanner.create(b, .{});
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");

    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);
    scanner.generate("xdg_wm_base", 2);
    scanner.generate("zxdg_decoration_manager_v1", 1);

    const wayland_bindings = b.createModule(.{ .root_source_file = scanner.result });
    const xkbcommon_bindings = b.dependency("zig-xkbcommon", .{}).module("xkbcommon");
    const pixman_bindings = b.dependency("zig-pixman", .{}).module("pixman");
    const wlroots_bindings = b.dependency("zig-wlroots", .{}).module("wlroots");

    wlroots_bindings.addImport("wayland", wayland_bindings);
    wlroots_bindings.addImport("xkbcommon", xkbcommon_bindings);
    wlroots_bindings.addImport("pixman", pixman_bindings);

    wlroots_bindings.resolved_target = target;
    wlroots_bindings.linkSystemLibrary("wlroots-0.18", .{});

    const hwc_exe = b.addExecutable(.{
        .name = "hwc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_check = b.addExecutable(.{
        .name = "parser",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check = b.step("check", "Check if parser compiles");
    check.dependOn(&exe_check.step);

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.0.1");
    hwc_exe.root_module.addOptions("build_options", options);

    hwc_exe.linkLibC();

    hwc_exe.root_module.addImport("ziglua", ziglua);

    hwc_exe.root_module.addImport("wayland", wayland_bindings);
    hwc_exe.root_module.addImport("xkbcommon", xkbcommon_bindings);
    hwc_exe.root_module.addImport("wlroots", wlroots_bindings);

    hwc_exe.linkSystemLibrary("wayland-server");
    hwc_exe.linkSystemLibrary("xkbcommon");
    hwc_exe.linkSystemLibrary("pixman-1");

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(hwc_exe);

    b.installArtifact(hwc_exe);
    const run_cmd = b.addRunArtifact(hwc_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "run hwc");
    run_step.dependOn(&run_cmd.step);
}
