const std = @import("std");
const vaxis = @import("vaxis");
const toml = @import("zig-toml");
const json = @import("json");
const known_folders = @import("known-folders");
const colours = @import("colours.zig");
// const re = @cImport(@cInclude("regez.h"));

pub const TREE_SITTER_QUERIES_PATH: []const u8 = "/flow/queries/";
pub const CONFIG_PATH: []const u8 = "/flow/config.json";
pub const THEME_PATH: []const u8 = "/flow/theme.config";

fn loadJson(allocator: std.mem.Allocator, path: []const u8, comptime T: type) error{ NoDotConfigDirectory, OutOfMemory }!T {
    const json_path = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
    defer allocator.free(json_path);
    const original_length = json_path.len;
    if (!allocator.resize(json_path, json_path.len + path.len)) {
        error.OutOfMemory;
    }
    @memcpy(json_path[original_length], path);
    const file = try std.fs.openFileAbsolute(json_path, .{ .mode = .read_only });
    const file_contents = try file.readToEndAlloc(allocator, json_path);
    defer allocator.free(file_contents);
    return json.fromSliceLeaky(allocator, file_contents);
}

// Mappings for literal file structure

pub const _ThemeHighlightStructure = struct {
    color: []const u8,
    underline: bool,
    italic: bool,
    bold: bool,
};
pub const _ThemeHighlightType = enum {
    ansi,
    string,
    structure,
};
const _ThemeHighlight = union(_ThemeHighlightType) {
    ansi: ?u8,
    string: ?[]const u8,
    structure: ?_ThemeHighlightStructure,

    inline fn ansiToColour(value: u8) vaxis.Color {
        return colours.colourFromANSI256(value);
    }

    fn hexToColour(value: []const u8) error{InvalidColour}!vaxis.Color {
        if (value.len != 7) {
            return error.InvalidColour;
        }
        var colour: u24 = 0x0;
        for (value[1..], 0..) |char, i| {
            switch (char) {
                '0'...'9' => colour |= (value - '0') << (20 - (i * 4)),
                'a'...'f' => colour |= (value - 'a' + 0xa) << (20 - (i * 4)),
                else => return error.InvalidColour,
            }
        }
        return vaxis.Color.rgbFromUint(colour);
    }

    fn stringToColour(value: []const u8) error{InvalidColour}!vaxis.Color {
        if (value.len == 0) {
            return error.InvalidColour;
        } else if (value[0] == '#') {
            return try hexToColour(value);
        }
        return colours.ANSI_NAMED.get(value) orelse error.InvalidColour;
    }

    pub fn internalise(self: *@This()) !ThemeHighlight {
        if (self.ansi) |ansi| {
            return try ansiToColour(ansi);
        } else if (self.string) |string| {
            return try stringToColour(string);
        } else if (self.structure) |structure| {
            return .{
                .color = try stringToColour(structure.color),
                .underline = structure.underline,
                .italic = structure.italic,
                .bold = structure.bold,
            };
        }
        return error.InvalidColour;
    }
};
pub const _Theme = std.StringHashMap(_ThemeHighlight);

// Transformed usable structures

const ThemeHighlight = struct {
    color: vaxis.Color,
    underline: bool,
    italic: bool,
    bold: bool,
};
pub const Theme = std.StringHashMap(ThemeHighlight);

fn loadTheme(allocator: std.mem.Allocator) !Theme {
    const theme_map = try loadJson(allocator, THEME_PATH, _Theme);
    theme_map.deinit();
    const theme = Theme.init(allocator);
    var iter = theme_map.iterator();
    while (iter.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        try theme.put(key, entry.value_ptr.internalise());
    }
    return theme;
}

pub const Properties = struct {
    spaces_per_tab: usize,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return try loadJson(allocator, CONFIG_PATH, @This());
    }

    pub fn deinit(_: *@This()) void {
        // Does nothing yet
    }

    pub const default: @This() = .{
        .spaces_per_tab = 4,
    };
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    properties: Properties,
    theme: ?Theme,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .allocator = allocator,
            .properties = Properties.init(allocator),
            .theme = Theme.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.properties.deinit();
        if (self.theme) |theme| {
            var iter = theme.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            theme.clearAndFree();
        }
    }

    pub const default: @This() = .{
        .properties = .default,
        .theme = null,
    };
};
