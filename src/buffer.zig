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

    inline fn isFinished(self: *FileBufferIterator) bool {
        if (self.end) |_end| {
            return self.offset < _end;
        }
        return true;
    }

    /// Caller is responsible for freeing the returned list
    pub fn next(self: *FileBufferIterator) !?std.ArrayList(u8) {
        var string = std.ArrayList(u8).init(self.allocator);
        errdefer string.deinit();
        while (self.isFinished()) : (self.offset += 1) {
            const char: u8 = self.piecetable.get(self.offset) catch {
                break;
            };
            try string.append(char);
            if (!std.mem.eql(u8, &.{char}, "\n")) {
                _ = self.piecetable.get(self.offset + 1) catch {
                    continue;
                };
            }
        }
        if (string.items.len == 0) {
            string.deinit();
            return null;
        }
        return string;
    }
};

pub const FileBuffer = struct {
    pub const MaxFileSize: u64 = 1 * 1024 * 1024 * 1024; // 1 GB

    file_buffer: []u8,
    piecetable: PieceTable,
    file_path: []const u8,
    allocator: std.mem.Allocator,
    buffer_line_range_indicies: ?Range,

    fn pieceTableFromFile(allocator: std.mem.Allocator, file_path: []const u8) !struct { []u8, PieceTable } {
        const file: std.fs.File = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
        defer file.close();
        const stats = try file.stat();
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        const buffer = try file.readToEndAlloc(allocator, @intCast(stats.size));
        return .{ buffer, try PieceTable.init(allocator, buffer) };
    }

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !FileBuffer {
        const pt = try FileBuffer.pieceTableFromFile(allocator, file_path);
        return .{
            .file_buffer = pt[0],
            .piecetable = pt[1],
            .file_path = file_path,
            .allocator = allocator,
            .buffer_line_range_indicies = null,
        };
    }

    pub fn deinit(self: *FileBuffer) void {
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
    }

    pub fn applyBufferWindow(self: *FileBuffer, height: usize) !void {
        if (self.buffer_line_range_indicies == null) {
            self.buffer_line_range_indicies = Range{
                .start = 0,
                .end = 0,
            };
        } else {
            self.buffer_line_range_indicies = Range{
                .start = self.buffer_line_range_indicies.?.start,
                .end = self.buffer_line_range_indicies.?.start,
            };
        }
        try self.updateBufferWindow(@intCast(height));
    }

    /// Move the buffer window up or down by a given amount of lines.
    /// A negative move amount will push the window up, whereas a positive
    /// value will move it down
    pub fn updateBufferWindow(self: *FileBuffer, move_amount: isize) !void {
        if (self.buffer_line_range_indicies == null or move_amount == 0) {
            return;
        }
        const line_direction: isize = std.math.sign(move_amount) + 1;
        var offset: isize = @intCast(self.buffer_line_range_indicies.?.start);
        var total_move = @abs(move_amount);
        while (total_move > 0) : (offset += line_direction) {
            const char: u8 = self.piecetable.get(@intCast(offset)) catch {
                return;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                total_move -= 1;
                _ = self.piecetable.get(@intCast(offset + line_direction)) catch {
                    break;
                };
            }
        }
        self.buffer_line_range_indicies.?.start = @intCast(offset);
        offset = @intCast(self.buffer_line_range_indicies.?.end);
        total_move = @abs(move_amount) + 1;
        while (total_move > 0) : (offset += line_direction) {
            const char: u8 = self.piecetable.get(@intCast(offset)) catch {
                return;
            };
            if (std.mem.eql(u8, &.{char}, "\n")) {
                total_move -= 1;
                _ = self.piecetable.get(@intCast(offset + line_direction)) catch {
                    break;
                };
            }
        }
        self.buffer_line_range_indicies.?.end = @intCast(offset);
    }
    pub fn cursorOffset(self: *FileBuffer, pos: Position) ?usize {
        var line: usize = self.buffer_line_range_indicies.?.start;
        var col: usize = 0;
        var offset: usize = 0;
        while (line <= self.buffer_line_range_indicies.?.end) : (offset += 1) {
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

    pub fn windowLineIterator(self: *FileBuffer) error{UninitialisedWindow}!FileBufferIterator {
        if (self.buffer_line_range_indicies == null) {
            return error.UninitialisedWindow;
        }
        return FileBufferIterator.init(
            self.allocator,
            self.piecetable,
            self.buffer_line_range_indicies.?.start,
            self.buffer_line_range_indicies.?.end,
        );
    }

    pub fn lineIterator(self: *FileBuffer) error{UninitialisedWindow}!FileBufferIterator {
        return FileBufferIterator.init(self.allocator, self.piecetable, 0, null);
    }

    pub fn save(self: *FileBuffer) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{ .mode = 0o666, .read = false, .truncate = true });
        var iterator = try self.lineIterator();
        while (try iterator.next()) |slice| {
            _ = try file.write(slice.items);
            defer slice.deinit();
        }
        file.close();
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
        const pt = try FileBuffer.pieceTableFromFile(self.allocator, self.file_path);
        self.file_buffer = pt[0];
        self.piecetable = pt[1];
    }
};
