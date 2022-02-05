const std = @import("std");

const SymbolSize = enum(u8) {
    @"8 bits" = 1,
    @"16 bits" = 2,
    @"32 bits" = 4,
    @"64 bits" = 8,
};

const magic_number = [4]u8{ 0xFB, 0xAD, 0xB6, 0x02 };

pub const View = struct {
    buffer: []const u8,

    symbol_size: SymbolSize,

    const InitError = error{ InvalidHeader, InvalidData };
    pub fn init(buffer: []const u8) InitError!View {
        if (!std.mem.startsWith(u8, buffer, &magic_number))
            return error.InvalidHeader;
        if (buffer.len < 28) return error.InvalidData;

        const export_table = std.mem.readIntLittle(u32, buffer[4..8]);
        const import_table = std.mem.readIntLittle(u32, buffer[8..12]);
        const string_table = std.mem.readIntLittle(u32, buffer[12..16]);
        const section_start = std.mem.readIntLittle(u32, buffer[16..20]);
        const section_size = std.mem.readIntLittle(u32, buffer[20..24]);
        const symbol_size = std.mem.readIntLittle(u8, buffer[24..25]);

        if (export_table >= buffer.len - 4) return error.InvalidData;
        if (import_table >= buffer.len - 4) return error.InvalidData;
        if (string_table >= buffer.len - 4) return error.InvalidData;
        if (section_start + section_size >= buffer.len) return error.InvalidData;

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

    // pub fn stringTable(self: View) ?StringTAble {
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

    pub fn iterator(self: SymbolTable) SymbolIterator {
        return SymbolIterator{ .table = self };
    }
};

pub const SymbolIterator = struct {
    table: SymbolTable,
    index: usize = 0,

    pub fn next(self: *SymbolIterator) ?Symbol {
        if (self.index >= self.table.count)
            return null;
        const index = self.index;
        self.index += 1;
        return self.table.get(index);
    }
};

pub const Symbol = struct {
    offset: u32,
    symbol_name: u32,
};

fn hexToBits(comptime str: []const u8) *const [str.len / 2]u8 {
    comptime {
        comptime var res: [str.len / 2]u8 = undefined;
        @setEvalBranchQuota(str.len);

        inline for (res) |*c, i| {
            c.* = std.fmt.parseInt(u8, str[2 * i ..][0..2], 16) catch unreachable;
        }
        return &res;
    }
}

test "parse empty, but valid file" {
    _ = try View.init(hexToBits("fbadb602000000000000000000000000000000000000000002000000"));
}

test "parse invalid header" {
    try std.testing.expectError(error.InvalidHeader, View.init(hexToBits("")));
    try std.testing.expectError(error.InvalidHeader, View.init(hexToBits("f2adb602")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb60200000000000000000000000000000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000000000000000000000000000")));

    //                                                                          EEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602190000000000000000000000000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000001900000000000000000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000019000000000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000000000001C0000000100000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000001D00000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000000000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000003000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000005000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000007000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000009000000")));
}

test "parse export table" {
    //                                    MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLNNNNNNN1OOOOOOO1NNNNNNN2OOOOOOO2NNNNNNN3OOOOOOO3
    const view = try View.init(hexToBits("fbadb6021C000000000000000000000000000000000000000200000003000000010000000200000003000000040000000500000006000000"));

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
    //                                    MMMMMMMMEEEEEEEEIIIIIIIISSSSSSSSssssssssllllllllBB______LLLLLLLLNNNNNNN1OOOOOOO1NNNNNNN2OOOOOOO2NNNNNNN3OOOOOOO3
    const view = try View.init(hexToBits("fbadb602000000001C0000000000000000000000000000000200000003000000010000000200000003000000040000000500000006000000"));

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
