const std = @import("std");
const known_folders = @import("known-folders");

pub const PATH_SEP: *const [1:0]u8 = std.fs.path.sep_str;

/// Caller is responsible for freeing returned slice
pub fn cwdName(allocator: std.mem.Allocator) ![]const u8 {
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const last_sep_index = std.mem.lastIndexOf(u8, cwd_path, PATH_SEP);
    if (last_sep_index == null) {
        return cwd_path;
    }
    defer allocator.free(cwd_path);
    const name = try allocator.alloc(u8, cwd_path.len - last_sep_index.?);
    @memcpy(name, cwd_path[last_sep_index.? + 1 ..]);
    return name;
}

/// Provided path is assumed to be non-relative, and result is a slice taken from given path
pub fn subPathRelativeToCwd(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);
    return path[path.len..];
}

pub fn lastPathElement(path: []const u8) []const u8 {
    const last_sep_index = std.mem.lastIndexOf(u8, path, PATH_SEP);
    if (last_sep_index == null) {
        return path;
    }
    return path[last_sep_index.? + 1 ..];
}

/// Computes the equivalent temp file for a file
/// being edited.
///
/// Caller is responsible for freeing returned slice
pub fn tempFilePath(allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    const cwd_relative_path = try subPathRelativeToCwd(allocator, file_path);
    const cwd_name = try cwdName(allocator);
    defer allocator.free(cwd_name);
    const file_name = lastPathElement(cwd_relative_path);
    const project_directories = try std.fmt.allocPrint(
        allocator,
        "{s}" ++ PATH_SEP ++ "{s}",
        .{ cwd_name, if (cwd_relative_path.len == file_name.len)
            ""
        else
            cwd_relative_path[0 .. cwd_relative_path.len - file_name.len - 1] },
    );
    defer allocator.free(project_directories);
    const cache_dir = try known_folders.open(
        allocator,
        known_folders.KnownFolder.cache,
        .{},
    ) orelse return error.NoCacheDirectory;
    try cache_dir.makePath(project_directories);
    return try std.fmt.allocPrint(
        allocator,
        "{s}" ++ PATH_SEP ++ "{s}",
        .{ cwd_name, cwd_relative_path },
    );
}
