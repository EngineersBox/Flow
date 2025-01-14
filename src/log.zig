const std = @import("std");

pub fn logToFile(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const file = try std.fs.createFileAbsolute("/Users/jackkilrain/Desktop/Projects/zig/Flow/out.log", .{ .truncate = false });
    defer file.close();
    const string = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(string);
    try file.writeAll(string);
}
