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

    // Caller is responsible for freeing the returned list
    pub fn next(self: *FileBufferIterator) !?std.ArrayList(u8) {
        // TODO: Iterate the lines!
        var string = std.ArrayList(u8).init(self.allocator);
        errdefer string.deinit();
        while (self.isFinished()) : (self.offset += 1) {
            const char: u8 = self.piecetable.get(self.offset) catch {
                break;
            };
            if (!std.mem.eql(u8, &.{char}, "\n")) {
                continue;
            }
            try string.append(char);
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

    piecetable: PieceTable,
    file_path: []const u8,
    allocator: std.mem.Allocator,
    buffer_line_range_indicies: ?Range,

    fn pieceTableFromFile(allocator: std.mem.Allocator, file_path: []const u8) !PieceTable {
        const file: std.fs.File = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
        defer file.close();
        const stats = try file.stat();
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        const buf = try file.readToEndAlloc(allocator, @intCast(stats.size));
        return try PieceTable.init(allocator, buf);
    }

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !FileBuffer {
        return .{
            .piecetable = try FileBuffer.pieceTableFromFile(allocator, file_path),
            .file_path = file_path,
            .allocator = allocator,
            .buffer_line_range_indicies = null,
        };
    }

    pub fn deinit(self: *FileBuffer) void {
        self.piecetable.deinit();
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
        try self.updateBufferWindow(height);
    }

    /// Move the buffer window up or down by a given amount of lines.
    /// A negative move amount will push the window up, whereas a positive
    /// value will move it down
    pub fn updateBufferWindow(self: *FileBuffer, move_amount: isize) !void {
        if (self.buffer_line_range_indicies == null or move_amount == 0) {
            return;
        }
        const line_direction: isize = std.math.sign(move_amount) + 1;
        var offset: usize = self.buffer_line_range_indicies.?.start;
        var total_move = @abs(move_amount);
        while (total_move > 0) : (offset += line_direction) {
            const char: u8 = self.piecetable.get(offset) catch {
                return;
            };
            if (std.mem.eql(u8, char, "\n")) {
                total_move -= 1;
            }
        }
        self.buffer_line_range_indicies.?.start = offset + line_direction;
        offset = self.buffer_line_range_indicies.?.end;
        total_move = @abs(move_amount) + 1;
        while (total_move > 0) : (offset += line_direction) {
            const char: u8 = self.piecetable.get(offset) catch {
                return;
            };
            if (std.mem.eql(u8, char, "\n")) {
                total_move -= 1;
            }
        }
        self.buffer_line_range_indicies.?.end = offset + line_direction;
    }
    pub fn cursorOffset(self: *FileBuffer, pos: Position) ?usize {
        // TODO: Make this check only within the window lines
        //       as the cursor will always reside within it.
        var line: usize = 0;
        var col: usize = 0;
        var offset: usize = 0;
        while (true) : (offset += 1) {
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

    pub fn windowLineIterator(self: *FileBuffer, line_start: usize, line_end: usize) FileBufferIterator {
        return FileBufferIterator.init(self.allocator, self.piecetable, line_start, line_end);
    }

    pub fn lineIterator(self: *FileBuffer) FileBufferIterator {
        return FileBufferIterator.init(self.allocator, self.piecetable, 0, null);
    }

    pub fn save(self: *FileBuffer) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{ .mode = 0o666, .read = false, .truncate = true });
        var iterator = self.lineIterator();
        while (try iterator.next()) |slice| {
            _ = try file.write(slice.items);
            defer slice.deinit();
        }
        file.close();
        self.piecetable.deinit();
        self.piecetable = try FileBuffer.pieceTableFromFile(self.allocator, self.file_path);
    }
};
