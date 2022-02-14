const std = @import("std");
const slf = @import("slf.zig");
const args_parser = @import("args");

pub fn printUsage(stream: anytype) !void {
    try stream.writeAll(
        \\slf-objdump [-h] [-i] [-e] [-s] [-r] [-d] [-x] [--raw] <file>
        \\
        \\Prints information about a SLF file. If no option is given, the return code
        \\will tell if the given <file> is a valid SLF file.
        \\
        \\The tables will always be print in the order imports, exports, relocations, strings, data.
        \\
        \\Options:
        \\  -h, --help      Prints this text.
        \\  -x, --all       Prints all tables.
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
    all: bool = false,

    pub const shorthands = .{
        .@"h" = "help",
        .@"i" = "imports",
        .@"e" = "exports",
        .@"s" = "strings",
        .@"r" = "relocs",
        .@"d" = "data",
        .@"x" = "all",
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

    if (cli.options.all) {
        cli.options.data = true;
        cli.options.imports = true;
        cli.options.exports = true;
        cli.options.strings = true;
        cli.options.relocs = true;
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

    var any_previous = false;
    for (cli.positionals) |file_name| {
        var arena = std.heap.ArenaAllocator.init(gpa.allocator());
        defer arena.deinit();

        if (cli.positionals.len > 1) {
            if (any_previous) try stdout.writeAll("\n");
            try stdout.writeAll(file_name);
            try stdout.writeAll(":\n");
            any_previous = true;
        }

        const file_data = std.fs.cwd().readFileAlloc(arena.allocator(), file_name, 1 << 30) catch |err| { // 1 GB max.
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
            if (any_previous) try stdout.writeAll("\n");
            if (view.imports()) |imports| {
                if (imports.count > 0) {
                    try stdout.writeAll("Imports:\n");
                    try printSymbolTable(stdout, string_table, imports);
                } else {
                    try stdout.writeAll("Empty import table.\n");
                }
            } else {
                try stdout.writeAll("No import table.\n");
            }
            any_previous = true;
        }
        if (cli.options.exports) {
            if (any_previous) try stdout.writeAll("\n");
            if (view.exports()) |exports| {
                if (exports.count > 0) {
                    try stdout.writeAll("Exports:\n");
                    try printSymbolTable(stdout, string_table, exports);
                } else {
                    try stdout.writeAll("Empty export table.\n");
                }
            } else {
                try stdout.writeAll("No export table.\n");
            }
            any_previous = true;
        }
        if (cli.options.relocs) {
            if (any_previous) try stdout.writeAll("\n");
            if (view.relocations()) |relocs| {
                if (relocs.count > 0) {
                    try stdout.writeAll("Relocations:\n");
                    var iter = relocs.iterator();
                    while (iter.next()) |offset| {
                        try stdout.print("- {X:0>8}\n", .{offset});
                    }
                } else {
                    try stdout.writeAll("Empty relocation table.\n");
                }
            } else {
                try stdout.writeAll("No relocation table.\n");
            }
            any_previous = true;
        }
        if (cli.options.strings) {
            if (any_previous) try stdout.writeAll("\n");
            if (string_table) |strings| {
                if (strings.limit > 4) {
                    try stdout.writeAll("Strings:\n");

                    var iter = strings.iterator();
                    while (iter.next()) |string| {
                        try stdout.print("- @{X:0>8} => \"{}\"\n", .{
                            string.offset,
                            std.fmt.fmtSliceEscapeUpper(string.text),
                        });
                    }
                } else {
                    try stdout.writeAll("Empty string table.\n");
                }
            } else {
                try stdout.writeAll("No string table.\n");
            }
            any_previous = true;
        }
        if (cli.options.data) {
            if (any_previous) try stdout.writeAll("\n");
            const dataset = view.data();

            if (dataset.len > 0) {
                try stdout.writeAll("Data:\n");

                var i: usize = 0;
                while (i < dataset.len) {
                    const limit = std.math.min(16, dataset.len - i);
                    try stdout.print("{X:0>8} {}\n", .{ i, std.fmt.fmtSliceHexLower(dataset[i..][0..limit]) });
                    i += limit;
                }
            } else {
                try stdout.writeAll("Empty data set.\n");
            }
            any_previous = true;
        }
    }

    return 0;
}
fn printSymbolTable(stream: anytype, strings: ?slf.StringTable, table: slf.SymbolTable) !void {
    var lpad: usize = 0;
    {
        var iter = table.iterator();
        while (iter.next()) |item| {
            const len = if (strings) |str|
                str.get(item.symbol_name).text.len
            else
                std.fmt.count("@{X:0>8}", .{item.symbol_name});
            lpad = std.math.max(lpad, len);
        }
    }
    {
        var iter = table.iterator();
        while (iter.next()) |item| {
            var buffer: [64]u8 = undefined;

            const name = if (strings) |str|
                @as([]const u8, str.get(item.symbol_name).text)
            else
                try std.fmt.bufPrint(&buffer, "@{X:0>8}", .{item.symbol_name});

            try stream.writeAll("- ");
            try stream.writeAll(name);
            try stream.writeByteNTimes(' ', lpad - name.len);

            try stream.print(" => {X:0>8}\n", .{item.offset});
        }
    }
}
