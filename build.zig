const std = @import("std");
const Scanner = @import("zig-wayland").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ziglua = b.dependency("ziglua", .{
        .target = target,
        .optimize = optimize,
        .lang = .lua51,
        .shared = true,
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

    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    const xkbcommon = b.dependency("zig-xkbcommon", .{}).module("xkbcommon");
    const pixman = b.dependency("zig-pixman", .{}).module("pixman");
    const wlroots = b.dependency("zig-wlroots", .{}).module("wlroots");

    wlroots.addImport("wayland", wayland);
    wlroots.addImport("xkbcommon", xkbcommon);
    wlroots.addImport("pixman", pixman);

    wlroots.resolved_target = target;
    wlroots.linkSystemLibrary("wlroots-0.18", .{});

    const hwc_exe = b.addExecutable(.{
        .name = "hwc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", "0.0.1");
    hwc_exe.root_module.addOptions("build_options", options);

    hwc_exe.linkLibC();

    hwc_exe.root_module.addImport("ziglua", ziglua);

    hwc_exe.root_module.addImport("wayland", wayland);
    hwc_exe.root_module.addImport("xkbcommon", xkbcommon);
    hwc_exe.root_module.addImport("wlroots", wlroots);

    hwc_exe.linkSystemLibrary("wayland-server");
    hwc_exe.linkSystemLibrary("xkbcommon");
    hwc_exe.linkSystemLibrary("pixman-1");
    hwc_exe.linkSystemLibrary("libinput");

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(hwc_exe);

    b.installArtifact(hwc_exe);
    const run_cmd = b.addRunArtifact(hwc_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
