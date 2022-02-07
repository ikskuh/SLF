const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const test_runner = b.addTest("src/slf.zig");

    const test_step = b.step("test", "Runs the test suite");
    test_step.dependOn(&test_runner.step);

    const ld = b.addExecutable("slf-ld", "src/main.zig");
    ld.setTarget(target);
    ld.setBuildMode(mode);
    ld.install();

    const link_run = ld.run();

    const run_step = b.step("run", "Runs the linker");
    run_step.dependOn(&link_run.step);
}
