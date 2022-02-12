const std = @import("std");
const slf = @import("slf.zig");
const args_parser = @import("args");

pub fn printUsage(stream: anytype) !void {
    try stream.writeAll(
        \\slf-ld [-h] [-o <file>] [-b <base>] [-s 8|16|32|64] [-a <align>] <object> ...
        \\
        \\Links several SLF files together into a single binary. At least one <object> file in SLF format must be present.
        \\
        \\Options:
        \\  -h, --help            Prints this text.
        \\  -o, --output <file>   The resulting binary file. Default is a.out.
        \\  -s, --symsize <size>  Defines the symbol size in bits. Allowed values are 8, 16, 32, and 64. Default is guessed by the first object file.
        \\  -a, --align <al>      Aligns each module to <al> bytes. <al> must be a power of two. Default is 16.
        \\  -b, --base <orig>     Modules start at offset <orig>. <orig> must be aligned. Default is 0x00000000.
        \\
    );
}

const CliOptions = struct {
    help: bool = false,
    output: ?[]const u8 = null,
    symsize: u8 = 16,
    @"align": u32 = 16,
    base: u32 = 0,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var stderr = std.io.getStdErr().writer();
    var stdout = std.io.getStdOut().writer();

    var args = args_parser.parseForCurrentProcess(CliOptions, gpa.allocator(), .print) catch return 1;
    defer args.deinit();

    if (args.options.help) {
        try printUsage(stdout);
        return 0;
    }
    if (args.positionals.len == 0) {
        try printUsage(stderr);
        return 1;
    }

    const symbol_size = std.meta.intToEnum(slf.SymbolSize, args.options.symsize / 8) catch {
        try stderr.print("{} is not a valid symbol size.\n", .{args.options.symsize});
        return 1;
    };

    if (!std.math.isPowerOfTwo(args.options.@"align")) {
        try stderr.print("{} is not a power of two.\n", .{args.options.@"align"});
        return 1;
    }

    if (!std.mem.isAligned(args.options.base, args.options.@"align")) {
        try stderr.print("{} is not aligned to {}.\n", .{ args.options.base, args.options.@"align" });
        return 1;
    }

    var linker = slf.Linker.init(gpa.allocator());
    defer linker.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    for (args.positionals) |file_name| {
        var file_data = std.fs.cwd().readFileAlloc(arena.allocator(), file_name, 1 << 30) catch |err| { // 1 GB max.
            switch (err) {
                error.FileNotFound => try stderr.print("The file {s} does not exist.\n", .{file_name}),
                else => |e| return e,
            }
            return 1;
        };
        errdefer arena.allocator().free(file_data);

        const view = slf.View.init(file_data, .{}) catch {
            try stderr.print("The file {s} does not seem to be a valid SLF file.\n", .{file_name});
            return 1;
        };

        try linker.addModule(view);
    }

    var result = try std.fs.cwd().createFile(args.options.output orelse "a.out", .{ .read = true });
    defer result.close();

    var stream = std.io.StreamSource{ .file = result };

    try linker.link(&stream, .{
        .symbol_size = symbol_size,
        .module_alignment = args.options.@"align",
        .base_address = args.options.base,
    });

    return 0;
}
