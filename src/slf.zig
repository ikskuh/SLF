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
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000190000000000000000000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000001900000000000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000019000000000000000002000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb6020000000000000000000000000000001C0000000102000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000001D02000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000000000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000003000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000005000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000007000000")));
    try std.testing.expectError(error.InvalidData, View.init(hexToBits("fbadb602000000000000000000000000000000000000000009000000")));
}
