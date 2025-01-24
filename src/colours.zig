const std = @import("std");
const vaxis = @import("vaxis");

pub const BLACK = vaxis.Color{ .rgb = .{ 0x25, 0x22, 0x21 } };
pub const WHITE = vaxis.Color{ .rgb = .{ 0xd4, 0xbe, 0x98 } };
pub const RED = vaxis.Color{ .rgb = .{ 0xFF, 0x00, 0x00 } };
pub const GREEN = vaxis.Color{ .rgb = .{ 0x00, 0xFF, 0x00 } };
pub const BLUE = vaxis.Color{ .rgb = .{ 0x00, 0x00, 0xFF } };
pub const YELLOW = vaxis.Color{ .rgb = .{ 0xFF, 0xFF, 0x00 } };
pub const CYAN = vaxis.Color{ .rgb = .{ 0x00, 0xFF, 0xFF } };
pub const MAGENTA = vaxis.Color{ .rgb = .{ 0xFF, 0x00, 0xFF } };

pub const ANSI_NAMED = std.StaticStringMap(vaxis.Color).initComptime(.{
    .{ "black", BLACK },
    .{ "BLACK", BLACK },
    .{ "red", RED },
    .{ "RED", RED },
    .{ "green", GREEN },
    .{ "GREEN", GREEN },
    .{ "yellow", YELLOW },
    .{ "YELLOW", YELLOW },
    .{ "blue", BLUE },
    .{ "BLUE", BLUE },
    .{ "magenta", MAGENTA },
    .{ "MAGENTA", MAGENTA },
    .{ "cyan", CYAN },
    .{ "CYAN", CYAN },
    .{ "white", WHITE },
    .{ "WHITE", WHITE },
});

const SYSTEM_COLOURS: [16]vaxis.Color = .{
    vaxis.Color.rgbFromUint(0x000000),
    vaxis.Color.rgbFromUint(0xcd0000),
    vaxis.Color.rgbFromUint(0x00cd00),
    vaxis.Color.rgbFromUint(0xcdcd00),
    vaxis.Color.rgbFromUint(0x0000ee),
    vaxis.Color.rgbFromUint(0xcd00cd),
    vaxis.Color.rgbFromUint(0x00cdcd),
    vaxis.Color.rgbFromUint(0xe5e5e5),
    vaxis.Color.rgbFromUint(0x7f7f7f),
    vaxis.Color.rgbFromUint(0xff0000),
    vaxis.Color.rgbFromUint(0x00ff00),
    vaxis.Color.rgbFromUint(0xffff00),
    vaxis.Color.rgbFromUint(0x5c5cff),
    vaxis.Color.rgbFromUint(0xff00ff),
    vaxis.Color.rgbFromUint(0x00ffff),
    vaxis.Color.rgbFromUint(0xffffff),
};

const CUBE_VALUE: [6]u24 = .{ 0, 95, 135, 175, 215, 255 };

pub fn colourFromANSI256(ansi: u8) vaxis.Color {
    if (ansi < 16) {
        return SYSTEM_COLOURS[ansi];
    } else if (ansi < 232) {
        const index = ansi - 16;
        return vaxis.Color.rgbFromUint((CUBE_VALUE[index / 36] << 16) | (CUBE_VALUE[(index / 6) % 6] << 8) | CUBE_VALUE[index % 6]);
    }
    const index = ((ansi - 232) * 10) + 8;
    return vaxis.Color.rgbFromUint(@as(u24, @intCast(index)) * 0x010101);
}
