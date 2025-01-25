const std = @import("std");
const vaxis = @import("vaxis");
const toml = @import("zig-toml");
const getty = @import("getty");
const json = @import("json");
const known_folders = @import("known-folders");
const colours = @import("colours.zig");
// const re = @cImport(@cInclude("regez.h"));

pub const TREE_SITTER_QUERIES_PATH: []const u8 = "/flow/queries/";
pub const CONFIG_PATH: []const u8 = "/flow/config.json";
pub const THEME_PATH: []const u8 = "/flow/theme.json";

const MaxFileSize: usize = 1 * 1024 * 1024 * 1024; // 1 GB

fn loadJson(allocator: std.mem.Allocator, comptime path: []const u8, comptime T: type) !std.json.Parsed(T) {
    const json_path = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
    defer allocator.free(json_path);
    const original_length = json_path.len;
    var full_path = try allocator.alloc(u8, json_path.len + path.len);
    defer allocator.free(full_path);
    @memcpy(full_path[0..json_path.len], json_path);
    @memcpy(full_path[original_length..], path);
    const file = try std.fs.openFileAbsolute(full_path, .{ .mode = .read_only });
    const file_contents = try file.readToEndAlloc(allocator, MaxFileSize);
    defer allocator.free(file_contents);
    return try std.json.parseFromSlice(T, allocator, file_contents, .{ .allocate = .alloc_always, .duplicate_field_behavior = .use_first });
}

const ThemeHighlightInternal = struct {
    colour: []const u8,
    underline: bool = false,
    italic: bool = false,
    bold: bool = false,
};

const ThemeInternal = std.json.ArrayHashMap(ThemeHighlightInternal);

// Mappings for literal file structure

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
