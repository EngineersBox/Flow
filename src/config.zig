const std = @import("std");
const vaxis = @import("vaxis");
const toml = @import("zig-toml");
const known_folders = @import("known-folders");
const colours = @import("colours.zig");
// const re = @cImport(@cInclude("regez.h"));

const PATH_SEP: *const [1:0]u8 = std.fs.path.sep_str;
pub const TREE_SITTER_QUERIES_PATH: []const u8 = PATH_SEP ++ "flow" ++ PATH_SEP ++ "queries" ++ PATH_SEP;
pub const CONFIG_PATH: []const u8 = PATH_SEP ++ "flow" ++ PATH_SEP ++ "config.json";
pub const THEME_PATH: []const u8 = PATH_SEP ++ "flow" ++ PATH_SEP ++ "theme.json";

const MaxFileSize: usize = 1 * 1024 * 1024 * 1024; // 1 GB

fn loadJson(allocator: std.mem.Allocator, comptime path: []const u8, comptime T: type) !std.json.Parsed(T) {
    const config_dir_path = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
    defer allocator.free(config_dir_path);
    const full_path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config_dir_path, path });
    defer allocator.free(full_path);
    const file = try std.fs.openFileAbsolute(full_path, .{ .mode = .read_only });
    const file_contents = try file.readToEndAlloc(allocator, MaxFileSize);
    defer allocator.free(file_contents);
    return try std.json.parseFromSlice(T, allocator, file_contents, .{ .allocate = .alloc_always, .duplicate_field_behavior = .use_first });
}

// Mappings for literal file structure

const ThemeHighlightInternal = struct {
    colour: []const u8,
    underline: bool = false,
    italic: bool = false,
    bold: bool = false,
};

const ThemeInternal = std.json.ArrayHashMap(ThemeHighlightInternal);

// Transformed structures from literal mappings

pub const ThemeHighlight = struct {
    colour: vaxis.Color,
    underline: bool,
    italic: bool,
    bold: bool,
};

pub const Theme = std.StringHashMap(ThemeHighlight);

fn loadTheme(allocator: std.mem.Allocator) !Theme {
    const internal_theme = try loadJson(allocator, THEME_PATH, ThemeInternal);
    defer internal_theme.deinit();
    var theme = Theme.init(allocator);
    var iter = internal_theme.value.map.iterator();
    while (iter.next()) |entry| {
        try theme.put(try allocator.dupe(u8, entry.key_ptr.*), ThemeHighlight{
            .colour = try colours.stringToColour(entry.value_ptr.colour),
            .underline = entry.value_ptr.underline,
            .italic = entry.value_ptr.italic,
            .bold = entry.value_ptr.bold,
        });
    }
    return theme;
}

pub const Properties = struct {
    spaces_per_tab: usize = 4,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    properties: std.json.Parsed(Properties),
    theme: Theme,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .allocator = allocator,
            .properties = try loadJson(allocator, CONFIG_PATH, Properties),
            .theme = try loadTheme(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.properties.deinit();
        var iter = self.theme.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.theme.clearAndFree();
    }
};
