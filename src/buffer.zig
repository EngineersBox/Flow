const std = @import("std");
const PieceTable = @import("piecetable").PieceTable;

/// A zero-indexed position of a buffer.
/// `line = 0, col = 0` is the first line, first character.
pub const Position = struct {
    line: usize,
    col: usize,
};

/// A range between two positions in a buffer. Inclusive.
pub const Range = struct {
    start: usize,
    end: usize,
};

pub const FileBufferIterator = struct {
    allocator: std.mem.Allocator,
    piecetable: PieceTable,
    offset: usize,
    end: ?usize,

    pub fn init(allocator: std.mem.Allocator, piecetable: PieceTable, start: usize, end: ?usize) FileBufferIterator {
        return .{
            .allocator = allocator,
            .piecetable = piecetable,
            .offset = start,
            .end = end,
        };
    }

    inline fn isFinished(self: *@This()) bool {
        if (self.end) |_end| {
            return self.offset < _end;
        }
        return true;
    }

    /// Caller is responsible for freeing the returned list
    pub fn next(self: *@This()) !?std.ArrayList(u8) {
        var string = std.ArrayList(u8).init(self.allocator);
        errdefer string.deinit();
        while (self.isFinished()) {
            const char: u8 = self.piecetable.get(self.offset) catch {
                break;
            };
            try string.append(char);
            // This here here and not in while statement
            // as it should always be incremented, regardless
            // of continue or break.
            self.offset += 1;
            if (std.mem.eql(u8, &.{char}, "\n")) {
                break;
            }
        }
        if (string.items.len == 0) {
            string.deinit();
            return null;
        }
        return string;
    }
};

pub const FileMeta = struct {
    lines: usize,
    size: usize,
};

pub const FileBuffer = struct {
    pub const MaxFileSize: u64 = 1 * 1024 * 1024 * 1024; // 1 GB

    file_buffer: []const u8,
    piecetable: PieceTable,
    file_path: []const u8,
    allocator: std.mem.Allocator,
    buffer_offset_range_indicies: ?Range,
    buffer_line_range_indicies: ?Range,
    meta: FileMeta,

    fn pieceTableFromFile(allocator: std.mem.Allocator, file_path: []const u8) !struct { []const u8, PieceTable } {
        const file: std.fs.File = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
        defer file.close();
        const stats: std.fs.File.Stat = try file.stat();
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        const buffer: []u8 = try file.readToEndAlloc(allocator, @intCast(stats.size));
        return .{ buffer, try PieceTable.init(allocator, buffer) };
    }

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !FileBuffer {
        const buf_and_piecetable: struct { []const u8, PieceTable } = try FileBuffer.pieceTableFromFile(allocator, file_path);
        return .{ .file_buffer = buf_and_piecetable[0], .piecetable = buf_and_piecetable[1], .file_path = file_path, .allocator = allocator, .buffer_offset_range_indicies = null, .buffer_line_range_indicies = null, .meta = .{ .lines = std.mem.count(u8, buf_and_piecetable[0], "\n") + 1, .size = buf_and_piecetable[0].len } };
    }

    pub fn deinit(self: *@This()) void {
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
    }

    pub fn insert(self: *@This(), index: usize, bytes: []const u8) error{ OutOfBounds, OutOfMemory }!void {
        try self.piecetable.insert(index, bytes);
        self.meta.lines += std.mem.count(u8, bytes, "\n");
        self.meta.size += bytes.len;
    }

    pub fn append(self: *@This(), bytes: []const u8) error{OutOfMemory}!void {
        try self.piecetable.append(bytes);
        self.meta.lines += std.mem.count(u8, bytes, "\n");
        self.meta.size += bytes.len;
    }

    pub fn set(self: *@This(), index: usize, value: u8) error{ OutOfBounds, OutOfMemory }!u8 {
        const result: u8 = try self.piecetable.set(index, value);
        if (value == '\n') {
            self.meta.lines += 1;
        }
        return result;
    }

    pub inline fn get(self: *@This(), index: usize) error{OutOfBounds}!u8 {
        return try self.piecetable.get(index);
    }

    pub fn delete(self: *@This(), index: usize, length: usize) error{ OutOfBounds, OutOfMemory }!void {
        var iterator = FileBufferIterator.init(self.allocator, self.piecetable, index, index + length);
        var lines: usize = 0;
        while (try iterator.next()) |line| : (lines += 1) {
            line.deinit();
        }
        try self.piecetable.delete(index, length);
        self.meta.lines -= lines;
        self.meta.size -= length;
    }

    /// Discard existing window and create a new one
    pub fn setBufferWindow(self: *@This(), start: usize, height: usize) error{StartExceedsSize}!void {
        var start_offset: usize = 0;
        var start_lines: usize = 0;
        while (start_lines < start) : (start_offset += 1) {
            const char: u8 = self.piecetable.get(@intCast(start_offset)) catch {
                return error.StartExceedsSize;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                start_lines += 1;
            }
        }
        var end_offset: usize = start_offset;
        var end_lines: usize = start_lines;
        while (end_lines < start + height) : (end_offset += 1) {
            const char: u8 = self.piecetable.get(@intCast(end_offset)) catch {
                break;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                end_lines += 1;
            }
        }
        self.buffer_offset_range_indicies = Range{
            .start = start_offset,
            .end = end_offset,
        };
        self.buffer_line_range_indicies = Range{
            .start = start_lines,
            .end = end_lines,
        };
    }

    /// Move the buffer window up or down by a given amount of lines.
    /// A negative move amount will push the window up, whereas a positive
    /// value will move it down
    ///
    /// Returns true of window is in buffer bounds, false otherwise
    pub fn updateBufferWindow(self: *@This(), move_amount: isize) !bool {
        if (self.buffer_offset_range_indicies == null or move_amount == 0) {
            return true;
        }
        const line_direction: isize = std.math.sign(move_amount) + 1;
        var start_offset: isize = @intCast(self.buffer_offset_range_indicies.?.start);
        var start_total_move = @abs(move_amount);
        while (start_total_move > 0) : (start_offset += line_direction) {
            const char: u8 = self.piecetable.get(@intCast(start_offset)) catch {
                return false;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                start_total_move -= 1;
                _ = self.piecetable.get(@intCast(start_offset + line_direction)) catch {
                    break;
                };
            }
        }
        var end_offset: isize = @intCast(self.buffer_offset_range_indicies.?.end);
        var end_total_move = @abs(move_amount) + 1;
        while (end_total_move > 0) : (end_offset += line_direction) {
            const char: u8 = self.piecetable.get(@intCast(end_offset)) catch {
                return false;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                end_total_move -= 1;
                _ = self.piecetable.get(@intCast(end_offset + line_direction)) catch {
                    break;
                };
            }
        }
        // Only apply new window if both start and end bounds are valid
        self.buffer_offset_range_indicies.?.start = @intCast(start_offset);
        self.buffer_offset_range_indicies.?.end = @intCast(end_offset);
        var start_line: isize = @intCast(self.buffer_line_range_indicies.?.start);
        start_line += @as(isize, @intCast(start_offset)) * std.math.sign(move_amount);
        self.buffer_line_range_indicies.?.start = @intCast(start_line);
        var end_line: isize = @intCast(self.buffer_line_range_indicies.?.end);
        end_line += @as(isize, @intCast(end_offset)) * std.math.sign(move_amount);
        self.buffer_line_range_indicies.?.end = @intCast(end_line);
        return true;
    }

    pub fn cursorOffsetInRange(self: *@This(), pos: Position, range: Range) !?usize {
        var line: usize = range.start;
        var col: usize = 0;
        var offset: usize = 0;
        while (line <= range.end) : (offset += 1) {
            const char: u8 = self.piecetable.get(offset) catch {
                break;
            };
            if (line == pos.line and col == pos.col) {
                return offset;
            }
            if (std.mem.eql(u8, &.{char}, "\n")) {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return null;
    }

    pub fn cursorOffset(self: *@This(), pos: Position) error{UninitialisedWindow}!?usize {
        if (self.buffer_offset_range_indicies == null) {
            return error.UninitialisedWindow;
        }
        var line: usize = self.buffer_offset_range_indicies.?.start;
        var col: usize = 0;
        var offset: usize = 0;
        while (line <= self.buffer_offset_range_indicies.?.end) : (offset += 1) {
            const char: u8 = self.piecetable.get(offset) catch {
                break;
            };
            if (line == pos.line and col == pos.col) {
                return offset;
            }
            if (std.mem.eql(u8, &.{char}, "\n")) {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        return null;
    }

    pub fn windowLineIterator(self: *@This()) error{UninitialisedWindow}!FileBufferIterator {
        if (self.buffer_offset_range_indicies == null) {
            return error.UninitialisedWindow;
        }
        return FileBufferIterator.init(
            self.allocator,
            self.piecetable,
            self.buffer_offset_range_indicies.?.start,
            self.buffer_offset_range_indicies.?.end,
        );
    }

    pub fn lineIterator(self: *@This()) error{UninitialisedWindow}!FileBufferIterator {
        return FileBufferIterator.init(self.allocator, self.piecetable, 0, null);
    }

    pub fn save(self: *@This()) !void {
        const file: std.fs.File = try std.fs.createFileAbsolute(self.file_path, .{ .mode = 0o666, .read = false, .truncate = true });
        var iterator: FileBufferIterator = try self.lineIterator();
        while (try iterator.next()) |slice| {
            _ = try file.write(slice.items);
            defer slice.deinit();
        }
        file.close();
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
        const buffer_and_piecetable: struct { []const u8, PieceTable } = try FileBuffer.pieceTableFromFile(self.allocator, self.file_path);
        self.file_buffer = buffer_and_piecetable[0];
        self.piecetable = buffer_and_piecetable[1];
    }
};
