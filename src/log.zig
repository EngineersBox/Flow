const std = @import("std");

pub fn logToFile(comptime fmt: []const u8, args: anytype) !void {
    const file = std.fs.cwd().openFile("/Users/jackkilrain/Desktop/Projects/zig/Flow/out.log", .{ .mode = .read_write }) catch return;
    defer file.close();
    file.seekFromEnd(0) catch return;
    file.writer().print(fmt, args) catch return;
}
