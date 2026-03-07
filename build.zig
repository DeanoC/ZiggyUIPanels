const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ziggy_ui = b.dependency("ziggy_ui", .{
        .target = target,
        .optimize = optimize,
    });

    const panels_mod = b.addModule("ziggy-ui-panels", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    panels_mod.addImport("ziggy-ui", ziggy_ui.module("ziggy-ui"));

    const lib = b.addLibrary(.{
        .name = "ziggy-ui-panels",
        .root_module = panels_mod,
        .linkage = .static,
    });
    b.installArtifact(lib);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("ziggy-ui", ziggy_ui.module("ziggy-ui"));

    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run ZiggyUIPanels tests");
    test_step.dependOn(&run_tests.step);
}
