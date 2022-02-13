const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const test_step = b.step("test", "Runs the test suite");
    const run_step = b.step("run", "Runs the linker");

    const test_runner = b.addTest("src/slf.zig");

    test_step.dependOn(&test_runner.step);

    const ld = b.addExecutable("slf-ld", "src/main.zig");
    ld.setTarget(target);
    ld.setBuildMode(mode);
    ld.addPackage(.{
        .name = "args",
        .path = .{ .path = "vendor/zig-args/args.zig" },
    });
    ld.install();

    const link_run = ld.run();
    if (b.args) |args| {
        link_run.addArgs(args);
    }

    run_step.dependOn(&link_run.step);

    addRunTest(test_step, ld, 1, &[_][]const u8{});
    addRunTest(test_step, ld, 0, &[_][]const u8{"--help"});
    addRunTest(test_step, ld, 1, &[_][]const u8{"foo/bar/bam/nonexisting.slf"});
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--symsize", "4", "foo/bar/bam/nonexisting.slf" });
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--align", "2", "foo/bar/bam/nonexisting.slf" });
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--base", "5", "foo/bar/bam/nonexisting.slf" });
}

fn addRunTest(test_step: *std.build.Step, exe: *std.build.LibExeObjStep, exit_code: u8, argv: []const []const u8) void {
    const run = exe.run();

    run.addArgs(argv);
    run.expected_exit_code = exit_code;
    run.stdout_action = .ignore;
    run.stderr_action = .ignore;

    test_step.dependOn(&run.step);
}
