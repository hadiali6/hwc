const std = @import("std");

const Scanner = @import("zig-wayland").Scanner;

const Context = struct {
    wayland_bindings: *std.Build.Module,
    wlroots_bindings: *std.Build.Module,
    pixman_bindings: *std.Build.Module,
    xkbcommon_bindings: *std.Build.Module,
    libinput_bindings: *std.Build.Module,
    hwc: *std.Build.Module,

    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    llvm: bool,
    omit_frame_pointer: bool,
    pie: bool,

    fn init(self: *Context, b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const strip = b.option(bool, "strip", "Omit debug information") orelse false;
        const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse false;
        const llvm = !(b.option(bool, "no-llvm", "(expirimental) Use non-LLVM x86 Zig backend") orelse false);

        const omit_frame_pointer = switch (optimize) {
            .Debug, .ReleaseSafe => false,
            .ReleaseFast, .ReleaseSmall => true,
        };

        const wayland_bindings = blk: {
            const scanner = Scanner.create(b, .{});

            addProtocols(b, scanner);
            generateProtocols(scanner);

            break :blk b.createModule(.{ .root_source_file = scanner.result });
        };
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

        self.* = .{
            .wayland_bindings = wayland_bindings,
            .wlroots_bindings = wlroots_bindings,
            .pixman_bindings = pixman_bindings,
            .xkbcommon_bindings = xkbcommon_bindings,
            .libinput_bindings = libinput_bindings,
            .hwc = hwc_module,

            .target = target,
            .optimize = optimize,
            .strip = strip,
            .llvm = llvm,
            .pie = pie,
            .omit_frame_pointer = omit_frame_pointer,
        };

        initModule(hwc_module, self.*);
    }
};

pub fn build(b: *std.Build) void {
    var context: Context = undefined;
    context.init(b);

    {
        const hwc_exe = b.addExecutable(options(b, context, .exe));
        initExe(hwc_exe, context);

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
        const hwc_exe_check = b.addExecutable(options(b, context, .exe));
        initExe(hwc_exe_check, context);

        const check = b.step("check", "Check if hwc compiles");
        check.dependOn(&hwc_exe_check.step);
    }

    {
        const hwc_exe_unit_tests = b.addTest(options(b, context, .@"test"));
        initExe(hwc_exe_unit_tests, context);

        const run_exe_unit_tests = b.addRunArtifact(hwc_exe_unit_tests);
        run_exe_unit_tests.has_side_effects = true;

        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_exe_unit_tests.step);
    }
}

fn addProtocols(b: *std.Build, scanner: *Scanner) void {
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("stable/tablet/tablet-v2.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");

    scanner.addCustomProtocol(b.path("protocol/wlr-layer-shell-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/wlr-output-power-management-unstable-v1.xml"));
    scanner.addCustomProtocol(b.path("protocol/hwc-status.xml"));
}

fn generateProtocols(scanner: *Scanner) void {
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

fn options(
    b: *std.Build,
    context: Context,
    comptime opt_type: enum { exe, @"test" },
) switch (opt_type) {
    .exe => std.Build.ExecutableOptions,
    .@"test" => std.Build.TestOptions,
} {
    return .{
        .name = "hwc",
        .root_source_file = b.path("src/main.zig"),
        .target = context.target,
        .optimize = context.optimize,
        .strip = context.strip,
        .use_llvm = context.llvm,
        .use_lld = context.llvm,
    };
}

fn initExe(exe: *std.Build.Step.Compile, context: Context) void {
    exe.pie = context.pie;

    initModule(&exe.root_module, context);

    exe.linkLibC();

    exe.linkSystemLibrary("libinput");
    exe.linkSystemLibrary("pixman-1");
    exe.linkSystemLibrary("wayland-server");
    exe.linkSystemLibrary("xkbcommon");
}

fn initModule(module: *std.Build.Module, context: Context) void {
    module.omit_frame_pointer = context.omit_frame_pointer;

    module.addImport("hwc", context.hwc);
    module.addImport("libinput", context.libinput_bindings);
    module.addImport("pixman", context.pixman_bindings);
    module.addImport("wayland", context.wayland_bindings);
    module.addImport("wlroots", context.wlroots_bindings);
    module.addImport("xkbcommon", context.xkbcommon_bindings);
}
