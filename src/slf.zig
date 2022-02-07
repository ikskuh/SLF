const std = @import("std");

pub const SymbolSize = enum(u8) {
    @"8 bits" = 1,
    @"16 bits" = 2,
    @"32 bits" = 4,
    @"64 bits" = 8,
};

const magic_number = [4]u8{ 0xFB, 0xAD, 0xB6, 0x02 };

pub const Linker = struct {
    const Module = struct {
        view: View,

        // will be defined in the link step
        base_offset: u32 = undefined,
    };

    allocator: std.mem.Allocator,
    modules: std.ArrayListUnmanaged(Module),

    pub fn init(allocator: std.mem.Allocator) Linker {
        return Linker{
            .allocator = allocator,
            .modules = .{},
        };
    }

    pub fn deinit(self: *Linker) void {
        self.modules.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn addModule(self: *Linker, module: View) !void {
        const ptr = try self.modules.addOne(self.allocator);
        ptr.* = Module{
            .view = module,
        };
    }

    pub const LinkOptions = struct {
        module_alignment: u32 = 16,
        symbol_size: ?SymbolSize = null,
    };
    pub fn link(self: *Linker, output: *std.io.StreamSource, options: LinkOptions) !void {
        if (self.modules.items.len == 0)
            return error.NothingToLink;

        var symbol_size: SymbolSize = options.symbol_size orelse self.modules.items[0].view.symbol_size;
        var write_offset: u32 = 0;
        for (self.modules.items) |*_module| {
            const module: *Module = _module;

            module.base_offset = write_offset;
            if (module.view.symbol_size != symbol_size)
                return error.MismatchingSymbolSize;

            write_offset += try std.math.cast(u32, std.mem.alignForward(module.view.data().len, options.module_alignment));
        }

        var symbol_table = std.StringHashMap(u64).init(self.allocator);
        defer symbol_table.deinit();

        const Patch = struct {
            offset: u64,
            symbol: []const u8,
        };

        var patches = std.ArrayList(Patch).init(self.allocator);
        defer patches.deinit();

        for (self.modules.items) |*_module| {
            const module: *Module = _module;

            std.log.debug("Process object file...", .{});

            try output.seekTo(module.base_offset);

            try output.writer().writeAll(module.view.data());

            // first resolve inputs
            if (module.view.imports()) |imports| {
                var strings = module.view.strings().?;
                var iter = imports.iterator();
                while (iter.next()) |sym| {
                    const string = strings.get(sym.symbol_name);

                    const symbol_offset = module.base_offset + sym.offset;

                    if (symbol_table.get(string.text)) |address| {
                        // we got that!
                        try output.seekTo(symbol_offset);
                        try patchStream(output, symbol_size, address);

                        std.log.debug("Directly resolving symbol {s} to {X:0>4} at offset {X:0>4}", .{ string.text, address, symbol_offset });
                    } else {
                        // we must patch this later
                        try patches.append(Patch{
                            .offset = symbol_offset,
                            .symbol = string.text,
                        });
                        std.log.debug("Adding patch for symbol {s} at offset {X:0>4}", .{ string.text, symbol_offset });
                    }
                }
            }

            // then publish outputs
            if (module.view.exports()) |exports| {
                var strings = module.view.strings().?;
                var iter = exports.iterator();
                while (iter.next()) |sym| {
                    const string = strings.get(sym.symbol_name);
                    try symbol_table.put(string.text, module.base_offset + sym.offset);

                    std.log.debug("Publishing symbol {s} at offset {X:0>4}", .{ string.text, module.base_offset + sym.offset });
                }
            }

            // then try resolving all patches
            {
                var i: usize = 0;
                while (i < patches.items.len) {
                    const patch = patches.items[i];

                    if (symbol_table.get(patch.symbol)) |address| {
                        try output.seekTo(patch.offset);
                        try patchStream(output, symbol_size, address);

                        std.log.debug("Patch-resolving symbol {s} to {X:0>4} at offset {X:0>4}", .{ patch.symbol, address, patch.offset });

                        // order isn't important at this point anymore
                        _ = patches.swapRemove(i);
                    } else {
                        i += 1;
                    }
                }
            }
        }

        {
            std.debug.print("symbols:\n", .{});

            var iter = symbol_table.iterator();
            while (iter.next()) |kv| {
                std.debug.print("{X:0>8}: {s}\n", .{ kv.value_ptr.*, kv.key_ptr.* });
            }
        }

        {
            std.debug.print("unresolved symbols:\n", .{});

            for (patches.items) |patch| {
                std.debug.print("{X:0>8}: {s}\n", .{ patch.offset, patch.symbol });
            }
        }
    }

    fn patchStream(stream: *std.io.StreamSource, size: SymbolSize, data: u64) !void {
        switch (size) {
            .@"8 bits" => try stream.writer().writeIntLittle(u8, try std.math.cast(u8, data)),
            .@"16 bits" => try stream.writer().writeIntLittle(u16, try std.math.cast(u16, data)),
            .@"32 bits" => try stream.writer().writeIntLittle(u32, try std.math.cast(u32, data)),
            .@"64 bits" => try stream.writer().writeIntLittle(u64, try std.math.cast(u64, data)),
        }
    }
};

/// A view of a SLF file. Allows accessing the data structure from a flat buffer without allocation.
pub const View = struct {
    buffer: []const u8,

    symbol_size: SymbolSize,

    pub const InitOptions = struct {
        validate_symbols: bool = false,
    };

    pub const InitError = error{ InvalidHeader, InvalidData };
    pub fn init(buffer: []const u8, options: InitOptions) InitError!View {
        if (!std.mem.startsWith(u8, buffer, &magic_number))
            return error.InvalidHeader;
        if (buffer.len < 28) return error.InvalidData;

        const export_table = std.mem.readIntLittle(u32, buffer[4..8]);
        const import_table = std.mem.readIntLittle(u32, buffer[8..12]);
        const string_table = std.mem.readIntLittle(u32, buffer[12..16]);
        const section_start = std.mem.readIntLittle(u32, buffer[16..20]);
        const section_size = std.mem.readIntLittle(u32, buffer[20..24]);
        const symbol_size = std.mem.readIntLittle(u8, buffer[24..25]);

        // validate basic boundaries
        if (export_table >= buffer.len - 4) return error.InvalidData;
        if (import_table >= buffer.len - 4) return error.InvalidData;
        if (string_table >= buffer.len - 4) return error.InvalidData;
        if (section_start + section_size > buffer.len) return error.InvalidData;

        const string_table_size = if (string_table != 0) blk: {
            const length = std.mem.readIntLittle(u32, buffer[string_table..][0..4]);
            if (string_table + length > buffer.len) return error.InvalidData;

            var offset: u32 = 4;
            while (offset < length) {
                const len = std.mem.readIntLittle(u32, buffer[string_table + offset ..][0..4]);
                // std.debug.print("{} + {} + 5 > {}\n", .{
                //     offset, len, length,
                // });
                if (offset + len + 5 > length) return error.InvalidData;
                if (string_table + len + 1 > buffer.len) return error.InvalidData;
                if (buffer[string_table + offset + len + 4] != 0) return error.InvalidData;
                offset += 5 + len;
            }
            break :blk length;
        } else 0;

        if (export_table != 0) {
            const count = std.mem.readIntLittle(u32, buffer[export_table..][0..4]);
            if (export_table + 8 * count + 4 > buffer.len) return error.InvalidData;

            var i: u32 = 0;
            while (i < count) : (i += 1) {
                const name_index = std.mem.readIntLittle(u32, buffer[export_table + 4 + 8 * i ..][0..4]);
                const offset = std.mem.readIntLittle(u32, buffer[export_table + 4 + 8 * i ..][4..8]);
                if (name_index + 5 > string_table_size) return error.InvalidData; // not possible for string table
                if (options.validate_symbols) {
                    if (offset + symbol_size > section_size) return error.InvalidData; // out of bounds
                }
            }
        }

        if (import_table != 0) {
            const count = std.mem.readIntLittle(u32, buffer[import_table..][0..4]);
            if (import_table + 8 * count + 4 > buffer.len) return error.InvalidData;

            var i: u32 = 0;
            while (i < count) : (i += 1) {
                const name_index = std.mem.readIntLittle(u32, buffer[import_table + 4 + 8 * i ..][0..4]);
                const offset = std.mem.readIntLittle(u32, buffer[import_table + 4 + 8 * i ..][4..8]);
                if (name_index + 5 > string_table_size) return error.InvalidData; // not possible for string table
                if (options.validate_symbols) {
                    if (offset + symbol_size > section_size) return error.InvalidData; // out of bounds
                }
            }
        }

        return View{
            .buffer = buffer,
            .symbol_size = std.meta.intToEnum(SymbolSize, symbol_size) catch return error.InvalidData,
        };
    }

    pub fn imports(self: View) ?SymbolTable {
        const import_table = std.mem.readIntLittle(u32, self.buffer[8..12]);
        if (import_table == 0)
            return null;
        return SymbolTable.init(self.buffer[import_table..]);
    }

    pub fn exports(self: View) ?SymbolTable {
        const export_table = std.mem.readIntLittle(u32, self.buffer[4..8]);
        if (export_table == 0)
            return null;
        return SymbolTable.init(self.buffer[export_table..]);
    }

    pub fn strings(self: View) ?StringTable {
        const string_table = std.mem.readIntLittle(u32, self.buffer[12..16]);
        if (string_table == 0)
            return null;
        return StringTable.init(self.buffer[string_table..]);
    }

    pub fn data(self: View) []const u8 {
        const section_start = std.mem.readIntLittle(u32, self.buffer[16..20]);
        const section_size = std.mem.readIntLittle(u32, self.buffer[20..24]);

        return self.buffer[section_start..][0..section_size];
    }
};

pub const SymbolTable = struct {
    buffer: []const u8,
    count: usize,

    pub fn init(buffer: []const u8) SymbolTable {
        const count = std.mem.readIntLittle(u32, buffer[0..4]);

        return SymbolTable{
            .count = count,
            .buffer = buffer[4..],
        };
    }

    pub fn get(self: SymbolTable, index: usize) Symbol {
        const symbol_name = std.mem.readIntLittle(u32, self.buffer[8 * index ..][0..4]);
        const offset = std.mem.readIntLittle(u32, self.buffer[8 * index ..][4..8]);

        return Symbol{
            .offset = offset,
            .symbol_name = symbol_name,
        };
    }

    pub fn iterator(self: SymbolTable) Iterator {
        return Iterator{ .table = self };
    }

    pub const Iterator = struct {
        table: SymbolTable,
        index: usize = 0,

        pub fn next(self: *Iterator) ?Symbol {
            if (self.index >= self.table.count)
                return null;
            const index = self.index;
            self.index += 1;
            return self.table.get(index);
        }
    };
};

pub const Symbol = struct {
    offset: u32,
    symbol_name: u32,
};

pub const StringTable = struct {
    buffer: []const u8,
    limit: u32,

    pub fn init(buffer: []const u8) StringTable {
        const limit = std.mem.readIntLittle(u32, buffer[0..4]);
        return StringTable{
            .limit = limit,
            .buffer = buffer,
        };
    }

    pub fn iterator(self: StringTable) Iterator {
        return Iterator{ .table = self };
    }

    pub fn get(self: StringTable, offset: u32) String {
        const length = std.mem.readIntLittle(u32, self.buffer[offset..][0..4]);

        return String{
            .offset = @truncate(u32, offset),
            .text = self.buffer[offset + 4 ..][0..length :0],
        };
    }

    pub const Iterator = struct {
        table: StringTable,
        offset: u32 = 4, // we start *after* the table length marker

        pub fn next(self: *Iterator) ?String {
            if (self.offset >= self.table.limit)
                return null;

            const string = self.table.get(self.offset);

            self.offset += 4; // skip length
            self.offset += @truncate(u32, string.text.len);
            self.offset += 1; // skip zero terminator

            return string;
        }
    };
};

pub const String = struct {
    offset: u32,
    text: [:0]const u8,
};

fn hexToBits(comptime str: []const u8) *const [str.len / 2]u8 {
    comptime {
        comptime var res: [str.len / 2]u8 = undefined;
        @setEvalBranchQuota(8 * str.len);

        inline for (res) |*c, i| {
            c.* = std.fmt.parseInt(u8, str[2 * i ..][0..2], 16) catch unreachable;
        }
        return &res;
    }
}

test "parse empty, but valid file" {
    _ = try View.init(hexToBits("fbadb602000000000000000000000000000000000000000002000000"), .{});
}

test "parse invalid header" {
    // Header too short:
    try std.testing.expectError(error.InvalidHeader, View.init(hexToBits(""), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidHeader, View.init(hexToBits("f2adb602"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000000000000000000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000000000000000000000000000"), .{ .validate_symbols = true }));

    // invalid/out of bounds header fields:

    //                                                                          EEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602190000000000000000000000000000000000000002000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000001900000000000000000000000000000002000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000019000000000000000000000002000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000000000001C0000000100000002000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000001D00000002000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000000000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000003000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000005000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000007000000"), .{ .validate_symbols = true }));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000009000000"), .{ .validate_symbols = true }));

    // out of bounds table size:

    // import table
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6021C00000000000000000000000000000000000000020000000300000001000000020000000300000004000000050000000600000"), .{ .validate_symbols = true }));

    // export table
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000001C000000000000000000000000000000020000000300000001000000020000000300000004000000050000000600000"), .{ .validate_symbols = true }));

    // string table
    //                                                                  MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLllllllllH e l l o ZZllllllllW o r l d ZZllllllllZ i g   i s   g r e a t ! ZZ
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0005000000576F726C64000D0000005A6967206973206772656174210"), .{})); // too short
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0105000000576F726C64000D0000005A69672069732067726561742100"), .{})); // non-null item
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0005000000576F726C64020D0000005A69672069732067726561742100"), .{})); // non-null item
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0005000000576F726C64000D0000005A69672069732067726561742103"), .{})); // non-null item
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0005000000576F726C64000E0000005A6967206973206772656174210000000000000000"), .{})); // item out of table
}

test "parse string table" {
    //                                    MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLllllllllH e l l o ZZllllllllW o r l d ZZllllllllZ i g   i s   g r e a t ! ZZ
    const view = try View.init(hexToBits("fbadb60200000000000000001C0000000000000000000000020000002A0000000500000048656C6C6F0005000000576F726C64000D0000005A69672069732067726561742100"), .{});

    const table = view.strings() orelse return error.MissingTable;

    var iter = table.iterator();
    try std.testing.expectEqualStrings("Hello", (iter.next() orelse return error.UnexpectedNull).text);
    try std.testing.expectEqualStrings("World", (iter.next() orelse return error.UnexpectedNull).text);
    try std.testing.expectEqualStrings("Zig is great!", (iter.next() orelse return error.UnexpectedNull).text);
    try std.testing.expectEqual(@as(?String, null), iter.next());
}

test "parse export table" {
    //                                    MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLNNNNNNN1OOOOOOO1NNNNNNN2OOOOOOO2NNNNNNN3OOOOOOO3LLLLLLLLllllllll..........................ZZ
    const view = try View.init(hexToBits("fbadb6021C000000000000003800000000000000080000000200000003000000010000000200000003000000040000000500000006000000160000000D000000FFFFFFFFFFFFFFFFFFFFFFFFFF00"), .{});

    const sym_1 = Symbol{ .symbol_name = 1, .offset = 2 };
    const sym_2 = Symbol{ .symbol_name = 3, .offset = 4 };
    const sym_3 = Symbol{ .symbol_name = 5, .offset = 6 };

    const table = view.exports() orelse return error.MissingTable;

    try std.testing.expectEqual(@as(usize, 3), table.count);

    try std.testing.expectEqual(sym_1, table.get(0));
    try std.testing.expectEqual(sym_2, table.get(1));
    try std.testing.expectEqual(sym_3, table.get(2));

    var iter = table.iterator();

    try std.testing.expectEqual(@as(?Symbol, sym_1), iter.next());
    try std.testing.expectEqual(@as(?Symbol, sym_2), iter.next());
    try std.testing.expectEqual(@as(?Symbol, sym_3), iter.next());
    try std.testing.expectEqual(@as(?Symbol, null), iter.next());
}

test "parse import table" {
    //                                    MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLNNNNNNN1OOOOOOO1NNNNNNN2OOOOOOO2NNNNNNN3OOOOOOO3LLLLLLLLllllllll..........................ZZ
    const view = try View.init(hexToBits("fbadb602000000001C0000003800000000000000080000000200000003000000010000000200000003000000040000000500000006000000160000000D000000FFFFFFFFFFFFFFFFFFFFFFFFFF00"), .{});

    const sym_1 = Symbol{ .symbol_name = 1, .offset = 2 };
    const sym_2 = Symbol{ .symbol_name = 3, .offset = 4 };
    const sym_3 = Symbol{ .symbol_name = 5, .offset = 6 };

    const table = view.imports() orelse return error.MissingTable;

    try std.testing.expectEqual(@as(usize, 3), table.count);

    try std.testing.expectEqual(sym_1, table.get(0));
    try std.testing.expectEqual(sym_2, table.get(1));
    try std.testing.expectEqual(sym_3, table.get(2));

    var iter = table.iterator();

    try std.testing.expectEqual(@as(?Symbol, sym_1), iter.next());
    try std.testing.expectEqual(@as(?Symbol, sym_2), iter.next());
    try std.testing.expectEqual(@as(?Symbol, sym_3), iter.next());
    try std.testing.expectEqual(@as(?Symbol, null), iter.next());
}
