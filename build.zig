const std = @import("std");

const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b.dependency("zig-wayland", .{}), .{});

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    scanner.addCustomProtocol(b.path("protocol/wlr-output-power-management-unstable-v1.xml"));

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);

    scanner.generate("xdg_wm_base", 6);

    scanner.generate("zwlr_output_power_manager_v1", 1);

    const wayland_bindings = b.createModule(.{ .root_source_file = scanner.result });
    const wlroots_bindings = b.dependency("zig-wlroots", .{}).module("wlroots");
    const pixman_bindings = b.dependency("zig-pixman", .{}).module("pixman");
    const xkbcommon_bindings = b.dependency("zig-xkbcommon", .{}).module("xkbcommon");

    wlroots_bindings.resolved_target = target;
    wlroots_bindings.addImport("wayland", wayland_bindings);
    wlroots_bindings.addImport("pixman", pixman_bindings);
    wlroots_bindings.addImport("xkbcommon", xkbcommon_bindings);
    wlroots_bindings.linkSystemLibrary("wlroots-0.18", .{
        .use_pkg_config = .yes,
        .needed = true,
    });

    const hwc_exe = b.addExecutable(.{
        .name = "hwc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    hwc_exe.root_module.addImport("wayland", wayland_bindings);
    hwc_exe.root_module.addImport("wlroots", wlroots_bindings);
    hwc_exe.root_module.addImport("pixman", pixman_bindings);

    hwc_exe.linkLibC();
    hwc_exe.linkSystemLibrary("wayland-server");
    hwc_exe.linkSystemLibrary("pixman-1");

    b.installArtifact(hwc_exe);

    const hwc_exe_check = b.addExecutable(.{
        .name = "hwc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    hwc_exe_check.root_module.addImport("wayland", wayland_bindings);
    hwc_exe_check.root_module.addImport("wlroots", wlroots_bindings);
    hwc_exe_check.root_module.addImport("pixman", pixman_bindings);
    hwc_exe_check.linkLibC();
    hwc_exe_check.linkSystemLibrary("wayland-server");
    hwc_exe_check.linkSystemLibrary("pixman-1");

    const check = b.step("check", "Check if hwc compiles");
    check.dependOn(&hwc_exe_check.step);

    const run_cmd = b.addRunArtifact(hwc_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run hwc");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
