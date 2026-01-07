const std = @import("std");
const zon = std.zon;
const Allocator = std.mem.Allocator;
const known_folders = @import("known-folders");

const LOCATIONS: [3]known_folders.KnownFolder = [_]known_folders.KnownFolder{
    .local_configuration,
    .roaming_configuration,
    .global_configuration,
};
const CONFIG_FILE_NAME = "flow.zon";

spaces_per_tab: usize = 4,

pub fn fromKnownLocationsOrDefault(gpa: Allocator) !@This() {
    for (LOCATIONS) |location| {
        var cfg_dir: []const u8 = undefined;
        if (try known_folders.getPath(gpa, location)) |cfg| {
            cfg_dir = cfg;
        } else {
            continue;
        }
        defer gpa.free(cfg_dir);
        var dir: std.fs.Dir = try std.fs.openDirAbsolute(cfg_dir, .{});
        defer dir.close();
        if (dir.openFile(
            CONFIG_FILE_NAME,
            .{ .mode = .read_only },
        )) |cfg_file| {
            defer cfg_file.close();
            return fromFile(gpa, cfg_file);
        } else |err| switch (err) {
            error.PermissionDenied, error.AccessDenied => {
                const path: []const u8 = dir.realpathAlloc(gpa, CONFIG_FILE_NAME) catch |err1| {
                    std.log.err(
                        "Failed to canonicalise config directory with config file name: {s}",
                        .{@errorName(err1)},
                    );
                    return @This(){};
                };
                std.log.warn(
                    "Failed to access config file {s}: {s}",
                    .{path, @errorName(err)},
                );
            },
            else => continue,
        }
    }
    return @This(){};
}

pub fn fromPath(gpa: Allocator, path: []const u8) !@This() {
    const file: std.fs.File = try std.fs.openFileAbsolute(
        path,
        .{ .mode = .read_only },
    );
    defer file.close();
    return fromFile(gpa, file);
}

pub fn fromFile(gpa: Allocator, file: std.fs.File) !@This() {
    var file_buffer: [4096]u8 = undefined;
    var reader: std.Io.Reader = file.reader(&file_buffer).interface;
    const data = try reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(data);
    var diag: zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);
    return zon.parse.fromSlice(
        @This(),
        gpa,
        data[0 .. data.len - 1 :0],
        &diag,
        .{
            .free_on_error = true,
        },
    );
}
