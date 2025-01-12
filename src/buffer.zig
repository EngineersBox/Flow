const std = @import("std");
const gb = @import("gap_buffer");

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

pub const FileBufferLine = struct {
    // Slice from buffer before gap
    first: ?[]u8,
    // Slice from buffer after gap
    second: ?[]u8,
};

pub const FileBufferIterator = struct {
    gap: *gb.GapBuffer(u8),
    first_range: ?Range,
    second_range: ?Range,
    first_index: ?usize,
    second_index: ?usize,

    pub fn init(gap: *gb.GapBuffer(u8), window_range: Range) FileBufferIterator {
        var first_range: ?Range = null;
        var second_range: ?Range = null;
        var first_index: ?usize = null;
        var second_index: ?usize = null;
        if (window_range.end < gap.items.len) {
            first_range = window_range;
            first_index = window_range.start;
        } else if (window_range.start < gap.items.len) {
            first_range = Range{
                .start = window_range.start,
                .end = gap.items.len - 1,
            };
            first_index = first_range.?.start;
            second_range = Range{
                .start = 0,
                .end = window_range.end - gap.items.len,
            };
        } else {
            second_range = Range{
                .start = window_range.start - gap.items.len,
                .end = window_range.end - gap.items.len,
            };
            second_index = second_range.?.start;
        }
        return .{
            .gap = gap,
            .first_range = first_range,
            .second_range = second_range,
            .first_index = first_index,
            .second_index = second_index,
        };
    }

    fn indexBuffer(self: *FileBufferIterator, i: usize) ?u8 {
        if (i < 0 or i > self.gap.capacity) {
            return null;
        } else if (i < self.gap.items.len) {
            return self.gap.items[i];
        }
        return self.gap.secondHalf()[i - self.gap.items.len];
    }

    pub fn next(self: *FileBufferIterator) FileBufferLine {
        // TODO: Iterate the lines!
        // NOTE: If the gap is within a line, then that line will be split across
        //       the first and second buffers. We could return a tuple from this
        //       method that has the first section only if the entire line is
        //       available in the first buffer and similarly for the second. It
        //       also allows for slices from the first and second buffer to be
        //       returned when the line is split between ranges.
        if (self.first_range) |range| {
            self.first_index = self.first_index orelse range.start;
            // Read line from index until either a newline or buffer exhausted
            // is reached. These cases should be distinguished as buffer exhausted
            // case necessitates reading from the after gap buffer until a newline
            // is found. If the second buffer is exhausted as well, then we return
            // both slices and ensure the iterator terminates after this call.
        }
    }
};

pub const FileBuffer = struct {
    pub const MaxFileSize: u64 = 1 * 1024 * 1024 * 1024; // 1 GB

    gap: gb.GapBuffer(u8),
    file_path: []const u8,
    allocator: std.mem.Allocator,
    buffer_line_range_indicies: ?Range,

    pub fn init(file_path: []const u8, allocator: std.mem.Allocator) !FileBuffer {
        // const stats = try std.os.fstat(fd);
        // if (stats.size > AnonMapSize) {
        //     return error.FileTooLarge;
        // }
        // const anon_ptr = try std.os.mmap(null, AnonMapSize, std.os.PROT_READ | std.os.PROT_WRITE, std.os.MAP_ANONYMOUS, null, 0);
        // const ptr = try std.os.mmap(anon_ptr, AnonMapSize, std.os.PROT_READ | std.os.PROT_WRITE, std.os.MAP_SHARED, fd, 0);
        const file: std.fs.File = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
        const stats = try file.stat();
        if (stats.size > MaxFileSize) {
            file.close();
            return error.FileTooLarge;
        }
        const buf = try file.readToEndAlloc(allocator, @intCast(stats.size));
        const gap = gb.GapBuffer(u8).fromOwnedSlice(allocator, buf);
        file.close();
        return .{
            .gap = gap,
            .file_path = file_path,
            .allocator = allocator,
            .buffer_line_range_indicies = null,
        };
    }

    pub fn deinit(self: *FileBuffer) void {
        self.gap.deinit();
    }

    pub fn applyBufferWindow(self: *FileBuffer, height: usize) void {
        self.buffer_line_range_indicies = Range{
            .start = 0,
            .end = self.cursorOffset(.{ .line = height, .col = 0 }) orelse @max(1, @max(self.gap.items.len, self.gap.capacity)) - 1,
        };
    }

    fn indexBuffer(self: *FileBuffer, i: usize) ?u8 {
        if (i < 0 or i > self.gap.capacity) {
            return null;
        } else if (i < self.gap.items.len) {
            return self.gap.items[i];
        }
        return self.gap.secondHalf()[i - self.gap.items.len];
    }

    /// Move the buffer window up or down by a given amount of lines.
    /// A negative move amount will push the window up, whereas a positive
    /// value will move it down
    pub fn updateBufferWindow(self: *FileBuffer, move_amount: isize) void {
        if (self.buffer_line_range_indicies == null or move_amount == 0) {
            return;
        }
        const line_direction: isize = std.math.sign(move_amount) + 1;
        var offset: usize = self.buffer_line_range_indicies.?.start;
        var total_move = @abs(move_amount);
        while (total_move > 0) : (offset += line_direction) {
            const char: ?u8 = self.indexBuffer(offset);
            if (char == null) {
                return;
            }
            if (std.mem.eql(u8, char.?, "\n")) {
                total_move -= 1;
            }
        }
        self.buffer_line_range_indicies.?.start = offset + line_direction;
        offset = self.buffer_line_range_indicies.?.end;
        total_move = @abs(move_amount) + 1;
        while (total_move > 0) : (offset += line_direction) {
            const char: ?u8 = self.indexBuffer(offset);
            if (char == null) {
                return;
            }
            if (std.mem.eql(u8, char.?, "\n")) {
                total_move -= 1;
            }
        }
        self.buffer_line_range_indicies.?.end = offset + line_direction;
    }

    pub fn cursorOffset(self: *FileBuffer, pos: Position) ?usize {
        // Taken from: https://github.com/lukewilson2002/zig-gap-buffer/blob/master/src/gap-buffer.zig
        if (self.gap.items.len == 0) {
            return 0;
        }
        const first_half = self.gap.items[0..self.gap.items.len];
        var line: usize = 0;
        var col: usize = 0;
        var offset: usize = 0;
        while (offset < first_half.len) : (offset += 1) {
            if (line == pos.line and col == pos.col) {
                return offset; // Have we found the correct position?
            }
            if (std.mem.eql(u8, first_half[offset], "\n")) {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        // If the position wasn't in the first half, it could be at the start of the gap
        if (line == pos.line and col == pos.col) {
            return self.gap.second_start;
        }
        const second_half = self.gap.secondHalf();
        offset = 0;
        while (offset < second_half.len) : (offset += 1) {
            if (line == pos.line and col == pos.col) {
                return self.gap.second_start + offset; // Have we found the correct position?
            }
            if (std.mem.eql(u8, second_half[offset], "\n")) {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        // If the position wasn't in the second half, it could be at the end of the buffer
        if (line == pos.line and col == pos.col) {
            return self.gap.capacity;
        }
        return null;
    }

    pub fn save(self: *FileBuffer) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{ .mode = 0o666, .read = false, .truncate = true });
        const slice: []u8 = try self.gap.toOwnedSlice();
        try file.writeAll(slice);
        self.gap.deinit();
        self.gap = gb.GapBuffer(u8).fromOwnedSlice(self.allocator, slice);
        file.close();
    }

    pub fn lineIterator(self: *FileBuffer) type {
        return FileBufferIterator.init(&self.gap, self.buffer_line_range_indicies);
    }
};
