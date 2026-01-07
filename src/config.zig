const std = @import("std");
const zon = std.zon;
const Allocator = std.mem.Allocator;
const known_folders = @import("known-folders");

const LOCATIONS: [3]known_folders.KnownFolder = [_]known_folders.KnownFolder{
    .local_configuration,
    .roaming_configuration,
    .global_configuration,
};
const CONFIG_FILE_NAME = "config.zon";

spaces_per_tab: usize = 4,

pub fn fromKnownLocationsOrDefault(gpa: Allocator) error{OutOfMemory,ParseZon}!@This() {
    for (LOCATIONS) |location| {
        var dir: std.fs.Dir = undefined;
        if (known_folders.open(
            gpa,
            location,
            .{
                .access_sub_paths = true,
            },
        ) catch |err| {
            std.log.debug(
                "Failed to open {s}: {s}\n",
                .{ @tagName(location), @errorName(err) },
            );
            continue;
        }) |d| {
            dir = d;
        } else {
            std.log.debug(
                "Directory {s} does not exist, skipping\n",
                .{@tagName(location)},
            );
            continue;
        }
        defer dir.close();
        var flow_dir: std.fs.Dir = dir.openDir(
            "flow",
            .{
                .access_sub_paths = true,
            },
        ) catch |err| {
            std.debug.print(
                "Failed to open subdirectory {s}: {s}\n",
                .{ @tagName(location), @errorName(err) },
            );
            continue;
        };
        defer flow_dir.close();
        std.debug.print("Found\n", .{});
        if (flow_dir.openFile(
            CONFIG_FILE_NAME,
            .{ .mode = .read_only },
        )) |cfg_file| {
            defer cfg_file.close();
            return try fromFile(gpa, cfg_file) orelse continue;
        } else |err| switch (err) {
            error.PermissionDenied, error.AccessDenied => {
                const path: []const u8 = dir.realpathAlloc(
                    gpa,
                    CONFIG_FILE_NAME,
                ) catch |err1| {
                    std.log.err(
                        "Failed to canonicalise config directory with config file name: {s}",
                        .{@errorName(err1)},
                    );
                    continue;
                };
                defer gpa.free(path);
                std.log.warn(
                    "Failed to access config file {s}: {s}, skipping",
                    .{ path, @errorName(err) },
                );
            },
            else => {
                std.log.warn(
                    "Unknown error accessing config file{s}: {s}, skipping\n",
                    .{ @tagName(location), @errorName(err) },
                );
                continue;
            },
        }
    }
    std.log.info("No viable config file found, using defaults", .{});
    return @This(){};
}

pub fn fromPath(gpa: Allocator, path: []const u8) error{OutOfMemory,ParseZon}!?@This() {
    const file: std.fs.File = std.fs.openFileAbsolute(
        path,
        .{ .mode = .read_only },
    ) catch |err| {
        std.log.err("Failed to open config path {s}: {s}", .{path, @errorName(err)},);
        return null;
    };
    defer file.close();
    return fromFile(gpa, file);
}

pub fn fromFile(gpa: Allocator, file: std.fs.File) error{OutOfMemory,ParseZon}!?@This() {
    const stat: std.fs.File.Stat = file.stat() catch |err| {
        std.log.err("Failed to stat config file: {s}", .{@errorName(err)});
        return null;
    };
    var data = try gpa.alloc(u8, stat.size + 1);
    data[data.len - 1] = 0;
    defer gpa.free(data);
    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(&file_buffer);
    reader.interface.readSliceAll(data[0 .. data.len - 1]) catch |err| {
        std.log.err("Failed to read config file data: {s}", .{@errorName(err)});
        return null;
    };
    var diag: zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);
    return try zon.parse.fromSlice(
        @This(),
        gpa,
        data[0 .. data.len - 1 :0],
        &diag,
        .{
            .free_on_error = true,
        },
    );
}
