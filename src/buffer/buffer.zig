const std = @import("std");
const PieceTable = @import("piecetable").PieceTable;
const known_folders = @import("known-folders");

const TreeSitter = @import("../lang/tree_sitter.zig").TreeSitter;
const _range = @import("../window/range.zig");
const Range = _range.Range;
const WindowRanges = _range.WindowRanges;
const Position = _range.Position;
const Config = @import("../config.zig").Config;
const _file_pager = @import("file_pager.zig");
const MmapPager = _file_pager.MmapPager;
const Page = _file_pager.Page;
const Files = @import("../files.zig");

pub const TempFile = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    file: std.fs.File,
    file_open: bool,
    pager: MmapPager,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !@This() {
        const temp_file_path = try Files.tempFilePath(allocator, file_path);
        errdefer allocator.free(temp_file_path);
        const cache_dir = try known_folders.open(
            allocator,
            known_folders.KnownFolder.cache,
            .{},
        ) orelse return error.NoCacheDirectory;
        const temp_file_exists = blk: {
            _ = cache_dir.statFile(temp_file_path) catch break :blk false;
            break :blk true;
        };
        if (temp_file_exists) {
            // TODO: Ask user if they want to recover or not
        } else {
            try std.fs.copyFileAbsolute(file_path, temp_file_path, .{});
        }
        const file = try std.fs.openFileAbsolute(temp_file_path, .{});
        return .{
            .allocator = allocator,
            .file_path = temp_file_path,
            .file = file,
            .file_open = true,
            .pager = MmapPager.init(allocator, file.handle),
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.file_open) {
            try self.file.close();
            self.file_open = false;
        }
        self.allocator.free(self.file_path);
        self.pager.deinit();
    }

    pub fn deleteTempFile(self: *@This()) !void {
        defer self.file_open = false;
        try self.pager.sync();
        self.file.close();
        try std.fs.deleteFileAbsolute(self.file_path);
    }
};

pub const BufferIterator = struct {
    allocator: std.mem.Allocator,
    piecetable: PieceTable,
    offset: usize,
    end: ?usize,
    has_returned_empty_on_ending_newline: bool,

    pub fn init(allocator: std.mem.Allocator, piecetable: PieceTable, start: usize, end: ?usize) BufferIterator {
        return .{
            .allocator = allocator,
            .piecetable = piecetable,
            .offset = start,
            .end = end,
            .has_returned_empty_on_ending_newline = false,
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
        var last_is_newline: bool = false;
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
                last_is_newline = true;
                break;
            }
        }
        if (string.items.len != 0) {
            return string;
        } else if (last_is_newline and !self.has_returned_empty_on_ending_newline) {
            self.has_returned_empty_on_ending_newline = true;
            return string;
        }
        string.deinit();
        return null;
    }
};

pub const FileMeta = struct {
    lines: usize,
    size: usize,
};

/// Single string optionally terminated with a newline
pub const Line = std.ArrayList(u8);
/// A sequential list of lines
pub const Lines = std.ArrayList(Line);

pub const Buffer = struct {
    pub const MaxFileSize: u64 = 1 * 1024 * 1024 * 1024; // 1 GB

    file_buffer: []const u8,
    temp_file: TempFile,
    piecetable: PieceTable,
    tree_sitter: ?TreeSitter,
    lines: Lines,
    file_path: []const u8,
    allocator: std.mem.Allocator,
    meta: FileMeta,

    pub fn initFromFile(allocator: std.mem.Allocator, config: Config, file_path: []const u8) !@This() {
        const structures: struct { []const u8, TempFile, PieceTable } = try Buffer.pieceTableFromFile(allocator, file_path);
        var extension: []const u8 = std.fs.path.extension(file_path);
        extension = std.mem.trimLeft(u8, extension, ".");
        const tree_sitter = try TreeSitter.initFromFileExtension(
            allocator,
            config,
            extension,
        );
        var lines = Lines.init(allocator);
        var iter = BufferIterator.init(
            allocator,
            structures[2],
            0,
            null,
        );
        while (try iter.next()) |line| {
            try lines.append(line);
        }
        return .{
            .file_buffer = structures[0],
            .temp_file = structures[1],
            .piecetable = structures[2],
            .tree_sitter = tree_sitter,
            .lines = lines,
            .file_path = file_path,
            .allocator = allocator,
            .meta = .{
                .lines = std.mem.count(u8, structures[0], "\n") + 1,
                .size = structures[0].len,
            },
        };
    }

    /// This takes ownership of the buffer, including freeing it when necessary
    pub fn initFromBuffer(_: std.mem.Allocator, _: []u8) !@This() {
        return error.MissingTempFileImplementation;
        // const piecetable = try PieceTable.init(allocator, buffer);
        // const formatted_buffer = try formatNewlines(allocator, buffer);
        // const lines = Lines.init(allocator);
        // var iter = BufferIterator.init(allocator, piecetable, 0, null);
        // while (try iter.next()) |line| {
        //     try lines.append(line);
        // }
        // return .{
        //     .file_buffer = formatted_buffer,
        //     .temp_file = undefined, // TODO: Randomly generate a file to use in temp directory
        //     .piecetable = piecetable,
        //     .tree_sitter = null,
        //     .lines = lines,
        //     .file_path = [0]u8{},
        //     .allocator = allocator,
        //     .meta = .{
        //         .lines = std.mem.count(u8, formatted_buffer, "\n") + 1,
        //         .size = formatted_buffer.len,
        //     },
        // };
    }

    pub fn deinit(self: *@This()) void {
        if (self.tree_sitter) |*ts| {
            ts.*.deinit();
        }
        for (self.lines.items) |*line| {
            line.*.deinit();
        }
        self.lines.deinit();
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
    }

    fn formatNewlines(allocator: std.mem.Allocator, buffer: []u8) ![]u8 {
        const new_buffer = try allocator.alloc(u8, buffer.len);
        const replace_count = std.mem.replace(u8, buffer, "\r\n", "\n", new_buffer);
        if (!allocator.resize(new_buffer, buffer.len - replace_count)) {
            return error.ResizeFormattedBufferFailed;
        }
        allocator.free(buffer);
        return new_buffer;
    }

    fn pieceTableFromFile(allocator: std.mem.Allocator, file_path: []const u8) !struct { []const u8, TempFile, PieceTable } {
        const file: std.fs.File = try std.fs.openFileAbsolute(file_path, .{ .mode = std.fs.File.OpenMode.read_only });
        defer file.close();
        const stats: std.fs.File.Stat = try file.stat();
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        var buffer: []u8 = try file.readToEndAlloc(allocator, @intCast(stats.size));
        buffer = try formatNewlines(allocator, buffer);
        return .{
            buffer,
            try TempFile.init(allocator, file_path),
            try PieceTable.init(allocator, buffer),
        };
    }

    pub fn insert(self: *@This(), index: usize, bytes: []const u8, ranges: *WindowRanges) error{ OutOfBounds, OutOfMemory }!void {
        if (bytes.len == 0) {
            return;
        }
        try self.piecetable.insert(index, bytes);
        const lines: usize = std.mem.count(u8, bytes, "\n");
        self.meta.lines += lines;
        self.meta.size += bytes.len;
        if (self.meta.lines < ranges.lines.maxEnd()) {
            ranges.lines.end += lines;
            ranges.offset.end += bytes.len;
            return;
        } else if (index > ranges.offset.end) {
            // Past the window, nothing to update
            return;
        } else if (lines == 0) {
            // No newlines, just update offsets
            if (index <= ranges.offset.start) {
                ranges.offset.start += bytes.len;
            }
            ranges.offset.end += bytes.len;
            return;
        }
        // At least one line added
        ranges.offset.end += bytes.len;
        var newlines_to_go_back = lines;
        while (newlines_to_go_back > 0) {
            ranges.offset.end -= 1;
            if (try self.get(ranges.offset.end) == '\n') {
                newlines_to_go_back -= 1;
            }
        }
        if (index >= ranges.offset.start) {
            return;
        }
        ranges.offset.start += bytes.len;
        newlines_to_go_back = lines + 1;
        while (newlines_to_go_back > 0 and ranges.offset.start >= 0) {
            if (try self.get(ranges.offset.start - 1) == '\n') {
                newlines_to_go_back -= 1;
            }
            ranges.offset.start -|= 1;
        }
        if (ranges.offset.start > 0) {
            // We will land on the newline behind the desired line
            // conditional on not being at the start of the buffer.
            // In this case we jump to next offset which is the start
            // of the desired line.
            ranges.offset.start += 1;
        }
    }

    pub fn append(self: *@This(), bytes: []const u8, ranges: *WindowRanges) error{OutOfMemory}!void {
        try self.piecetable.append(bytes);
        const lines = std.mem.count(u8, bytes, "\n");
        self.meta.lines += lines;
        const prev_size = self.meta.size;
        self.meta.size += bytes.len;
        if (self.meta.lines < ranges.lines.maxEnd()) {
            ranges.lines.end += lines;
            ranges.offset.end += bytes.len;
            return;
        } else if (prev_size -| 1 > ranges.offset.end) {
            // Past the window, nothing to update
            return;
        } else if (lines == 0) {
            // No newlines, just update offsets
            if (prev_size -| 1 <= ranges.offset.start) {
                ranges.offset.start += bytes.len;
            }
            ranges.offset.end += bytes.len;
            return;
        }
        // At least one line added
        ranges.offset.end += bytes.len;
        var newlines_to_go_back = lines;
        while (newlines_to_go_back > 0) {
            ranges.offset.end -= 1;
            if (try self.get(ranges.offset.end) == '\n') {
                newlines_to_go_back -= 1;
            }
        }
    }

    pub fn set(self: *@This(), index: usize, value: u8, ranges: *WindowRanges) error{ OutOfBounds, OutOfMemory }!u8 {
        const result: u8 = try self.piecetable.set(index, value);
        if (value != '\n') {
            return result;
        }
        if (self.meta.lines < ranges.lines.maxEnd()) {
            ranges.lines.end += 1;
            return;
        } else if (index > ranges.offset.end) {
            // Past the window, nothing to update
            return;
        }
        // At least one line added
        var newlines_to_go_back = 1;
        while (newlines_to_go_back > 0) {
            ranges.offset.end -= 1;
            if (try self.get(ranges.offset.end) == '\n') {
                newlines_to_go_back -= 1;
            }
        }
        if (index >= ranges.offset.start) {
            return;
        }
        newlines_to_go_back = 2;
        while (newlines_to_go_back > 0 and ranges.offset.start >= 0) {
            if (try self.get(ranges.offset.start - 1) == '\n') {
                newlines_to_go_back -= 1;
            }
            ranges.offset.start -|= 1;
        }
        if (ranges.offset.start > 0) {
            // We will land on the newline behind the desired line
            // conditional on not being at the start of the buffer.
            // In this case we jump to next offset which is the start
            // of the desired line.
            ranges.offset.start += 1;
        }
        return result;
    }

    pub inline fn get(self: *@This(), index: usize) error{OutOfBounds}!u8 {
        return try self.piecetable.get(index);
    }

    fn deleteAfterWindow(self: *@This(), index: usize, length: usize) error{ OutOfBounds, OutOfMemory }!void {
        var iterator = BufferIterator.init(self.allocator, self.piecetable, index, index + length);
        var lines: usize = 0;
        var current_offset = index;
        while (try iterator.next()) |line| : (lines += 1) {
            current_offset += line.items.len - 1;
            line.deinit();
        }
        try self.piecetable.delete(index, length);
        self.meta.lines -= lines;
        self.meta.size -= length;
    }

    fn deleteAfterWindowStart(self: *@This(), index: usize, length: usize, ranges: *WindowRanges) error{ OutOfBounds, OutOfMemory }!void {
        var offset = ranges.offset.start;
        var lines_from_start_to_index: usize = 0;
        while (offset <= index) : (offset += 1) {
            if (try self.get(offset) == '\n') {
                lines_from_start_to_index += 1;
            }
        }
        if (index == ranges.offset.start) {
            offset = index;
        }
        var lines: usize = 0;
        while (offset < index + length) : (offset += 1) {
            if (try self.get(offset) == '\n') {
                lines += 1;
            }
        }
        try self.piecetable.delete(index, length);
        self.meta.lines -|= lines;
        self.meta.size -|= length;
        ranges.offset.end = index;
        var lines_to_add_to_end = (ranges.lines.end - ranges.lines.start) - lines_from_start_to_index;
        ranges.lines.end = lines_from_start_to_index;
        offset = index;
        var lines_added: usize = 0;
        while (lines_to_add_to_end > 0 and offset < self.meta.size -| 1) : (offset += 1) {
            const char = self.get(offset) catch {
                break;
            };
            if (char == '\n') {
                lines_to_add_to_end -= 1;
                lines_added += 1;
            }
        }
        ranges.offset.end = offset;
        ranges.lines.end += lines_added;
    }

    fn deleteBeforeWindowStart(self: *@This(), index: usize, length: usize, ranges: *WindowRanges) error{ OutOfBounds, OutOfMemory }!void {
        var offset = index;
        var start_adjument_lines: usize = 0;
        var lines: usize = 0;
        while (offset <= index + length) : (offset += 1) {
            if (try self.get(offset) != '\n') {
                continue;
            }
            lines += 1;
            if (offset < ranges.offset.start) {
                start_adjument_lines += 1;
            }
        }
        var line_start_before_index: usize = index;
        while (line_start_before_index >= 0 and try self.get(line_start_before_index) != '\n') : (line_start_before_index -= 1) {}
        try self.piecetable.delete(index, length);
        self.meta.lines -= lines;
        self.meta.size -= length;
        offset = line_start_before_index;
        while (start_adjument_lines > 0 and offset < self.meta.size -| 1) : (offset += 1) {
            const char = self.get(offset) catch break;
            if (char == '\n') {
                start_adjument_lines -= 1;
            }
        }
        ranges.* = try self.setBufferWindow(offset, ranges.offset.max_diff.?);
    }

    pub fn delete(self: *@This(), index: usize, length: usize, ranges: *WindowRanges) error{ OutOfBounds, OutOfMemory }!void {
        if (index + length > self.meta.size) {
            return error.OutOfBounds;
        }
        if (index > ranges.offset.end) {
            try self.deleteAfterWindow(index, length);
            return;
        } else if (index >= ranges.offset.start) {
            try self.deleteAfterWindowStart(index, length, ranges);
            return;
        }
        try self.deleteBeforeWindowStart(index, length, ranges);
    }

    /// Discard existing window and create a new one
    pub fn setBufferWindow(self: *@This(), start: usize, height: usize) error{OutOfBounds}!WindowRanges {
        var start_offset: usize = 0;
        var start_lines: usize = 0;
        while (start_lines < start) : (start_offset += 1) {
            const char: u8 = self.piecetable.get(@intCast(start_offset)) catch {
                return error.OutOfBounds;
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
        return .{
            .offset = .{
                .start = start_offset,
                .end = end_offset -| 1,
                .max_diff = null,
            },
            .lines = .{
                .start = start_lines,
                .end = end_lines,
                .max_diff = height,
            },
        };
    }

    /// Move the buffer window up or down by a given amount of lines.
    /// A negative move amount will push the window up, whereas a positive
    /// value will move it down
    ///
    /// Returns true of window is in buffer bounds, false otherwise
    pub fn updateBufferWindow(self: *@This(), move_amount: isize, ranges: *WindowRanges) !bool {
        if (move_amount == 0) {
            return true;
        }
        const line_direction: isize = std.math.sign(move_amount) + 1;
        var start_offset: isize = @intCast(ranges.offset.start);
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
        var end_offset: isize = @intCast(ranges.offset.end);
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
        ranges.offset.start = @intCast(start_offset);
        ranges.offset.end = @intCast(end_offset);
        var start_line: isize = @intCast(ranges.lines.start);
        start_line += @as(isize, @intCast(start_offset)) * std.math.sign(move_amount);
        ranges.lines.start = @intCast(start_line);
        var end_line: isize = @intCast(ranges.lines.end);
        end_line += @as(isize, @intCast(end_offset)) * std.math.sign(move_amount);
        ranges.lines.end = @as(usize, @intCast(end_line)) -| 1;
        return true;
    }

    pub fn cursorOffsetInRange(self: *@This(), pos: Position, ranges: *WindowRanges) !?usize {
        var line: usize = ranges.lines.start;
        var col: usize = 0;
        var offset: usize = 0;
        while (line <= ranges.line.end) : (offset += 1) {
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

    pub fn cursorOffset(self: *@This(), pos: Position, ranges: *WindowRanges) ?usize {
        var line: usize = ranges.offset.start;
        var col: usize = 0;
        var offset: usize = 0;
        while (line <= ranges.offset.end) : (offset += 1) {
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

    pub fn windowLineIterator(self: *@This(), ranges: *WindowRanges) !BufferIterator {
        return BufferIterator.init(
            self.allocator,
            self.piecetable,
            ranges.offset.start,
            ranges.offset.end,
        );
    }

    pub fn lineIterator(self: *@This()) !BufferIterator {
        return BufferIterator.init(self.allocator, self.piecetable, 0, null);
    }

    pub fn reprocessRange(self: *@This(), line_range: Range) !void {
        if (self.tree_sitter) |*ts| {
            var modified_range_size: usize = 0;
            for (line_range.start..line_range.end) |i| {
                const line: *Line = &self.lines.items[i];
                modified_range_size += line.items.len;
            }
            try ts.*.reprocessRange(
                modified_range_size,
                &self.lines,
                line_range,
            );
        }
    }

    pub fn clearLines(self: *@This()) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.clearAndFree();
    }

    /// Returns true when lines are cached, false if cache already exists
    pub fn cacheLines(self: *@This()) !bool {
        if (self.lines.items.len != 0) {
            return false;
        }
        var line_iterator: BufferIterator = try self.lineIterator();
        while (try line_iterator.next()) |line| {
            try self.lines.append(line);
        }
        return true;
    }

    pub fn parseIntoTreeSitter(self: *@This()) !void {
        if (self.tree_sitter == null) {
            return;
        }
        try self.tree_sitter.?.parseBuffer(self.file_buffer, &self.lines);
    }

    pub fn save(self: *@This()) !void {
        if (self.file_path.len == 0) {
            return error.NoFilePathForBufferLiteral;
        }
        const file: std.fs.File = try std.fs.createFileAbsolute(self.file_path, .{ .mode = 0o666, .read = false, .truncate = true });
        var iterator: BufferIterator = try self.lineIterator();
        while (try iterator.next()) |slice| {
            _ = try file.write(slice.items);
            defer slice.deinit();
        }
        file.close();
        self.piecetable.deinit();
        self.allocator.free(self.file_buffer);
        const buffer_and_piecetable: struct { []const u8, PieceTable } = try Buffer.pieceTableFromFile(self.allocator, self.file_path);
        self.file_buffer = buffer_and_piecetable[0];
        self.piecetable = buffer_and_piecetable[1];
    }
};
