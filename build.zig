const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const test_runner = b.addTest("src/slf.zig");

    const test_step = b.step("test", "Runs the test suite");
    test_step.dependOn(&test_runner.step);
}
