const std = @import("std");
const slf = @import("slf.zig");
const args_parser = @import("args");

pub fn printUsage(stream: anytype) !void {
    try stream.writeAll(
        \\slf-objdump [-h] [-i] [-e] [-s] [-r] [-d] [--raw] <file>
        \\
        \\Prints information about a SLF file. If no option is given, the return code
        \\will tell if the given <file> is a valid SLF file.
        \\
        \\The tables will always be print in the order imports, exports, relocations, strings, data.
        \\
        \\Options:
        \\  -h, --help      Prints this text.
        \\  -i, --imports   Prints the import table.
        \\  -e, --exports   Prints the export table.
        \\  -s, --strings   Prints the string table with all entries.
        \\  -r, --relocs    Prints the table of relocations.
        \\  -d, --data      Prints the data in "canonical" hex format.
        \\      --raw       Dumps the raw section data to stdout. This option is mutual exclusive to all others.
        \\
    );
}

const CliOptions = struct {
    help: bool = false,
    imports: bool = false,
    exports: bool = false,
    strings: bool = false,
    relocs: bool = false,
    data: bool = false,
    raw: bool = false,

    pub const shorthands = .{
        .@"h" = "help",
        .@"i" = "imports",
        .@"e" = "exports",
        .@"s" = "strings",
        .@"r" = "relocs",
        .@"d" = "data",
    };
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var stderr = std.io.getStdErr().writer();
    var stdout = std.io.getStdOut().writer();

    var cli = args_parser.parseForCurrentProcess(CliOptions, gpa.allocator(), .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(stdout);
        return 0;
    }

    const invalid_combo = cli.options.raw and
        (cli.options.data or
        cli.options.imports or
        cli.options.exports or
        cli.options.strings or
        cli.options.relocs);

    if (invalid_combo) {
        try stderr.writeAll("--raw and other options are mutually exclusive.\n");
        return 1;
    }

    if (cli.positionals.len == 0) {
        try printUsage(stderr);
        return 1;
    }

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const file_name = cli.positionals[0];

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

    if (cli.options.raw) {
        try stdout.writeAll(view.data());
        return 0;
    }

    const string_table = view.strings();

    if (cli.options.imports) {
        if (view.imports()) |imports| {
            _ = imports;
            @panic("listing imports not implemented yet.");
        } else {
            try stdout.writeAll("No import table.\n");
        }
    }
    if (cli.options.exports) {
        if (view.exports()) |exports| {
            _ = exports;
            @panic("listing exports not implemented yet.");
        } else {
            try stdout.writeAll("No export table.\n");
        }
    }
    if (cli.options.relocs) {
        if (view.relocations()) |relocs| {
            _ = relocs;
            @panic("listing relocations not implemented yet.");
        } else {
            try stdout.writeAll("No relocation table.\n");
        }
    }
    if (cli.options.strings) {
        if (string_table) |strings| {
            _ = strings;
            @panic("listing string table not implemented yet.");
        } else {
            try stdout.writeAll("No string table table.\n");
        }
    }
    if (cli.options.data) {
        const dataset = view.data();

        var i: usize = 0;
        while (i < dataset.len) {
            const limit = std.math.min(16, dataset.len - i);
            try stdout.print("{X:0>8} {}\n", .{ i, std.fmt.fmtSliceHexLower(dataset[i..][0..limit]) });
            i += limit;
        }
    }

    return 0;
}
