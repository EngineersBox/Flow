const std = @import("std");
const Allocator = std.mem.Allocator;

const Datetime = @import("datetime").datetime.Datetime;
const ncz = @import("external/notcurses.zig");
const nc = ncz.nc;

pub const LoggerInitError = error{} || std.fs.File.OpenError;

pub const LogLevel = enum {
    ERROR,
    WARNING,
    INFO,
    DEBUG,
    TRACE,
};

pub const Logger = struct {
    gpa: Allocator,
    file: std.fs.File,
    writer_buffer: [4096]u8,
    file_writer: std.Io.Writer,
    stdplane: *nc.ncplane,

    pub fn init(gpa: Allocator, file_path: []const u8, stdplane: *nc.ncplane) LoggerInitError!@This() {
        var file: std.fs.File = try std.fs.createFileAbsolute(file_path, .{});
        var writer_buffer: [4096]u8 = std.mem.zeroes([4096]u8);
        return .{
            .gpa = gpa,
            .file = file,
            .writer_buffer = writer_buffer,
            .file_writer = file.writer(&writer_buffer).interface,
            .stdplane = stdplane,
        };
    }

    pub fn deinit(self: *@This()) !void {
        defer self.file.close();
        try self.file_writer.flush();
    }

    fn log(
        self: @This(),
        comptime level: LogLevel,
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        const formatted_msg: []const u8 = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(formatted_msg);
        const timestamp: []const u8 = try Datetime.now().formatISO8601(self.gpa, true);
        defer self.gpa.free(timestamp);
        try self.file_writer.print(
            "[{s}] [{s}] [" ++ module ++ "] " ++ @tagName(level) ++ " :: {s}\n",
            .{
                timestamp,
                std.Thread.getCurrentId(),
                formatted_msg,
            },
        );
    }

    pub fn err(
        self: @This(),
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.log(
            LogLevel.ERROR,
            module,
            fmt,
            args,
        );
    }

    pub fn warn(
        self: @This(),
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.log(
            LogLevel.WARN,
            module,
            fmt,
            args,
        );
    }

    pub fn info(
        self: @This(),
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.log(
            LogLevel.INFO,
            module,
            fmt,
            args,
        );
    }

    pub fn debug(
        self: @This(),
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.log(
            LogLevel.DEBUG,
            module,
            fmt,
            args,
        );
    }

    pub fn trace(
        self: @This(),
        comptime module: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) void {
        self.log(
            LogLevel.TRACE,
            module,
            fmt,
            args,
        );
    }
};

pub fn standard_log_file(_: Allocator, name: []const u8) []const u8 {
    // TODO: Implement this
    return name;
}
