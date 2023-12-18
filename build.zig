const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const release = b.option(bool, "release", "whether to build the bin in ReleaseSafe mode") orelse false;
    var mode = b.option(std.builtin.Mode, "mode", "optimization mode to build the bin") orelse .Debug;
    if (release) {
        mode = std.builtin.Mode.ReleaseSafe;
    }
    const exe = b.addExecutable(.{
        .name = "april",

        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = mode,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
