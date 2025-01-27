const std = @import("std");

const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    initProtocols(b, scanner);

    const wayland_bindings = b.createModule(.{ .root_source_file = scanner.result });
    const wlroots_bindings = b.dependency("zig-wlroots", .{}).module("wlroots");
    const pixman_bindings = b.dependency("zig-pixman", .{}).module("pixman");
    const xkbcommon_bindings = b.dependency("zig-xkbcommon", .{}).module("xkbcommon");
    const libinput_bindings = b.dependency("zig-libinput", .{}).module("libinput");

    wlroots_bindings.resolved_target = target;
    wlroots_bindings.addImport("wayland", wayland_bindings);
    wlroots_bindings.addImport("pixman", pixman_bindings);
    wlroots_bindings.addImport("xkbcommon", xkbcommon_bindings);
    wlroots_bindings.linkSystemLibrary("wlroots-0.18", .{
        .use_pkg_config = .yes,
        .needed = true,
    });

    const hwc_module = b.createModule(.{ .root_source_file = b.path("src/hwc.zig") });
    hwc_module.addImport("hwc", hwc_module);
    hwc_module.addImport("wayland", wayland_bindings);
    hwc_module.addImport("wlroots", wlroots_bindings);
    hwc_module.addImport("libinput", libinput_bindings);
    hwc_module.addImport("xkbcommon", xkbcommon_bindings);

    {
        const hwc_exe = b.addExecutable(.{
            .name = "hwc",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        hwc_exe.root_module.addImport("hwc", hwc_module);
        hwc_exe.root_module.addImport("wayland", wayland_bindings);
        hwc_exe.root_module.addImport("wlroots", wlroots_bindings);
        hwc_exe.root_module.addImport("libinput", libinput_bindings);
        hwc_exe.root_module.addImport("xkbcommon", xkbcommon_bindings);

        hwc_exe.linkLibC();

        hwc_exe.linkSystemLibrary("wayland-server");
        hwc_exe.linkSystemLibrary("pixman-1");
        hwc_exe.linkSystemLibrary("libinput");
        hwc_exe.linkSystemLibrary("xkbcommon");

        b.installArtifact(hwc_exe);

        const run_cmd = b.addRunArtifact(hwc_exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run hwc");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const hwc_exe_check = b.addExecutable(.{
            .name = "hwc",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        hwc_exe_check.root_module.addImport("hwc", hwc_module);
        hwc_exe_check.root_module.addImport("wayland", wayland_bindings);
        hwc_exe_check.root_module.addImport("wlroots", wlroots_bindings);
        hwc_exe_check.root_module.addImport("libinput", libinput_bindings);
        hwc_exe_check.root_module.addImport("xkbcommon", xkbcommon_bindings);

        hwc_exe_check.linkLibC();

        hwc_exe_check.linkSystemLibrary("libinput");
        hwc_exe_check.linkSystemLibrary("pixman-1");
        hwc_exe_check.linkSystemLibrary("wayland-server");
        hwc_exe_check.linkSystemLibrary("xkbcommon");

        const check = b.step("check", "Check if hwc compiles");
        check.dependOn(&hwc_exe_check.step);
    }

    {
        const hwc_exe_unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        hwc_exe_unit_tests.root_module.addImport("hwc", hwc_module);
        hwc_exe_unit_tests.root_module.addImport("wayland", wayland_bindings);
        hwc_exe_unit_tests.root_module.addImport("wlroots", wlroots_bindings);
        hwc_exe_unit_tests.root_module.addImport("libinput", libinput_bindings);
        hwc_exe_unit_tests.root_module.addImport("xkbcommon", xkbcommon_bindings);

        hwc_exe_unit_tests.linkLibC();

        hwc_exe_unit_tests.linkSystemLibrary("libinput");
        hwc_exe_unit_tests.linkSystemLibrary("pixman-1");
        hwc_exe_unit_tests.linkSystemLibrary("wayland-server");
        hwc_exe_unit_tests.linkSystemLibrary("xkbcommon");

        const run_exe_unit_tests = b.addRunArtifact(hwc_exe_unit_tests);

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}

fn initProtocols(b: *std.Build, scanner: *Scanner) void {
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");

    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/wlr-output-power-management-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/hwc-status.xml"));

    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 2);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);

    scanner.generate("xdg_wm_base", 6);

    scanner.generate("zwlr_layer_shell_v1", 5);
    scanner.generate("zwlr_output_power_manager_v1", 1);

    scanner.generate("zwp_pointer_gestures_v1", 3);
    scanner.generate("zwp_tablet_manager_v2", 1);

    scanner.generate("hwc_status_manager", 1);
}
