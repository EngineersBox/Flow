const std = @import("std");
const toml = @import("zig-toml");
const json = @import("json");
const known_folders = @import("known-folders");

pub const TREE_SITTER_QUERIES_PATH: []const u8 = "/flow/queries/";
pub const CONFIG_PATH: []const u8 = "/flow/config.json";

pub const ThemeHighlightStructure = struct {};
pub const ThemeHighlightType = enum {
    ansi,
    string,
    structure,
};
pub const ThemeHighlight = struct {
    color: []const u8,
    underline: bool,
    italic: bool,
    bold: bool,
};
pub const Theme = std.StringHashMap(ThemeHighlight);

pub const Config = struct {
    spaces_per_tab: usize,
    theme: ?Theme,

    pub fn init(allocator: std.mem.Allocator) !@This() {
        const dot_config_path = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
        defer allocator.free(dot_config_path);
        const original_length = dot_config_path.len;
        if (!allocator.resize(dot_config_path, dot_config_path.len + CONFIG_PATH.len)) {
            error.OutOfMemory;
        }
        @memcpy(dot_config_path[original_length], CONFIG_PATH);
        const file = try std.fs.openFileAbsolute(dot_config_path, .{ .mode = .read_only });
        const file_contents = try file.readToEndAlloc(allocator, dot_config_path);
        defer allocator.free(file_contents);
        return json.fromSliceLeaky(allocator, @This(), file_contents) catch return default;
    }

    pub const default: @This() = .{
        .spaces_per_tab = 4,
        .theme = null,
    };
};
