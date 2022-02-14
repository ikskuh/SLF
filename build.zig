const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const test_step = b.step("test", "Runs the test suite");
    const run_step = b.step("run", "Runs the linker");

    const test_runner = b.addTest("src/slf.zig");

    test_step.dependOn(&test_runner.step);

    const objdump = b.addExecutable("slf-objdump", "src/objdump.zig");
    objdump.setTarget(target);
    objdump.setBuildMode(mode);
    objdump.addPackage(.{
        .name = "args",
        .path = .{ .path = "vendor/zig-args/args.zig" },
    });
    objdump.install();

    const ld = b.addExecutable("slf-ld", "src/ld.zig");
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
    addRunTest(test_step, ld, 1, &[_][]const u8{"zig-out/nonexisting.slf"});
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--symsize", "4", "zig-out/nonexisting.slf" });
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--align", "2", "zig-out/nonexisting.slf" });
    addRunTest(test_step, ld, 1, &[_][]const u8{ "--base", "5", "zig-out/nonexisting.slf" });

    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-x" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-x" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-i" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-e" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-s" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-r" });
    addRunTest(test_step, objdump, 1, &[_][]const u8{ "--raw", "-d" });
    addRunTest(test_step, objdump, 0, &[_][]const u8{"data/crt0.slf"});
    addRunTest(test_step, objdump, 0, &[_][]const u8{ "-x", "data/crt0.slf" });
    addRunTest(test_step, objdump, 0, &[_][]const u8{ "-x", "data/crt0.slf", "data/library.slf" });
}

fn addRunTest(test_step: *std.build.Step, exe: *std.build.LibExeObjStep, exit_code: u8, argv: []const []const u8) void {
    const run = exe.run();

    run.addArgs(argv);
    run.expected_exit_code = exit_code;
    run.stdout_action = .ignore;
    run.stderr_action = .ignore;

    test_step.dependOn(&run.step);
}
