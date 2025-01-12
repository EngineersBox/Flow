const std = @import("std");
const gb = @import("gap_buffer");

/// A zero-indexed position of a buffer.
/// `line = 0, col = 0` is the first line, first character.
pub const Position = struct {
    line: usize,
    col: usize,
};

pub const FileBuffer = struct {
    pub const MaxFileSize: u64 = 1 * 1024 * 1024 * 1024; // 1 GB

    gap: gb.GapBuffer(u8),
    file_path: []const u8,
    allocator: std.mem.Allocator,

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
        };
    }

    pub fn deinit(self: *FileBuffer) void {
        self.gap.deinit();
    }

    pub fn cursorOffset(self: *FileBuffer, pos: Position) ?usize {
        // Taken from: https://github.com/lukewilson2002/zig-gap-buffer/blob/master/src/gap-buffer.zig
        if (self.gap.items.len == 0) {
            return 0;
        }
        const first_half = self.gap.items[0..self.gap.items.len];
        var line: usize = 0;
        var col: usize = 0;
        var iter = std.unicode.Utf8View.initUnchecked(first_half).iterator();
        var offset: usize = 0;
        while (iter.nextCodepointSlice()) |c| : (offset += c.len) {
            if (line == pos.line and col == pos.col) {
                return offset; // Have we found the correct position?
            }
            if (std.mem.eql(u8, c, "\n")) {
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
        iter = std.unicode.Utf8View.initUnchecked(second_half).iterator();
        offset = 0;
        while (iter.nextCodepointSlice()) |c| : (offset += c.len) {
            if (line == pos.line and col == pos.col) {
                return self.gap.second_start + offset; // Have we found the correct position?
            }
            if (std.mem.eql(u8, c, "\n")) {
                line += 1;
                col = 0;
            } else {
                col += 1;
            }
        }
        // If the position wasn't in the second half, it could be at the end of the buffer
        if (line == pos.line and col == pos.col) {
            return self.data.items.len;
        }
        return null;
    }

    pub fn save(self: *FileBuffer) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{ .mode = std.fs.File.OpenMode.write_only, .read = false, .truncate = true });
        const slice: []u8 = try self.gap.toOwnedSlice();
        try file.writeAll(slice);
        self.gap.deinit();
        self.gap = gb.GapBuffer(u8).fromOwnedSlice(self.allocator, slice);
        file.close();
    }
};
