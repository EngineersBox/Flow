const std = @import("std");
const toml = @import("zig-toml");
const known_folders = @import("known-folders");

pub const TREE_SITTER_QUERIES_PATH: []const u8 = "/flow/queries/";
pub const CONFIG_PATH: []const u8 = "/flow/config.toml";

// pub const Config = struct {
//     spaces_per_tab: usize,
//
//     pub fn init(allocator: std.mem.Allocator) anyerror!toml.Parsed(@This()) {
//         var parser = toml.Parser(@This()).init(allocator);
//         defer parser.deinit();
//         var path = try known_folders.getPath(allocator, .roaming_configuration) orelse return error.ConfigNotFound;
//         const prev_path_len = path.len;
//         if (!allocator.resize(path, path.len + CONFIG_PATH.len)) {
//             return error.OutOfMemory;
//         }
//         defer allocator.free(path);
//         @memcpy(path[prev_path_len..], CONFIG_PATH);
//         return try parser.parseFile(path);
//     }
// };

spaces_per_tab: usize,

pub const default: @This() = .{
    .spaces_per_tab = 4,
};
