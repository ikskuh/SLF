const std = @import("std");
const slf = @import("slf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var linker = slf.Linker.init(gpa.allocator());
    defer linker.deinit();

    try linker.addModule(try slf.View.init(@embedFile("../data/crt0.slf"), .{}));
    try linker.addModule(try slf.View.init(@embedFile("../data/main.slf"), .{}));
    try linker.addModule(try slf.View.init(@embedFile("../data/library.slf"), .{}));

    var result = try std.fs.cwd().createFile("result.bin", .{ .read = true });
    defer result.close();

    var stream = std.io.StreamSource{ .file = result };

    try linker.link(&stream, .{ .module_alignment = 256 });
}
