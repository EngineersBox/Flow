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

pub const FileBufferIterator = struct {
    gap: *gb.GapBuffer(u8),
    window_range: Range,
    utf8_iter: std.unicode.Utf8Iterator,

    pub fn init(gap: *gb.GapBuffer(u8), window_range: Range) FileBufferIterator {
        return .{
            .gap = gap,
            .window_range = window_range,
            .utf8_iter = std.unicode.Utf8View.initUnchecked(gap.items[0..gap.items.len]).iterator(),
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

    pub fn next(self: *FileBufferIterator) ?[]u8 {
        // TODO: Iterate the lines!
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
        while (total_move > 0): (offset += line_direction) {
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
        while (total_move > 0): (offset += line_direction) {
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
