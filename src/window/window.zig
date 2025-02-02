const std = @import("std");
const vaxis = @import("vaxis");

const _buffer = @import("../buffer/buffer.zig");
const Buffer = _buffer.Buffer;
const Line = _buffer.Line;
const colours = @import("../colours.zig");
const _range = @import("range.zig");
const Range = _range.Range;
const WindowRanges = _range.WindowRanges;
const Position = _range.Position;

/// Limited view over a buffer as a line and column range
pub const Window = struct {
    window: vaxis.Window,
    buffer: ?*Buffer,
    ranges: ?WindowRanges,

    pub fn init(window: vaxis.Window) @This() {
        return .{
            .window = window,
            .buffer = null,
            .ranges = null,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.window = undefined;
        self.buffer = null;
        self.ranges = null;
    }

    pub fn bindBuffer(self: *@This(), buffer: *Buffer) !void {
        self.buffer = buffer;
        if (self.ranges) |*ranges| {
            ranges.* = try self.buffer.?.setBufferWindow(0, self.window.height);
        }
    }

    pub fn setBufferWindow(self: *@This(), start: usize, height: usize) !void {
        if (self.buffer == null) {
            std.log.err("Cannot set window as buffer not bound", .{});
            return;
        }
        self.buffer.?.clearLines();
        self.ranges = try self.buffer.?.setBufferWindow(start, height);
        _ = try self.buffer.?.cacheLines();
    }

    pub fn updateBufferWindow(self: *@This(), offset_row: isize) !bool {
        if (self.buffer == null or offset_row < 0 and self.ranges.?.offset.start < @abs(offset_row)) {
            return false;
        } else if (offset_row > 0 and self.buffer.?.meta.size - 1 - self.ranges.?.offset.end < @abs(offset_row)) {
            return false;
        }
        self.buffer.?.clearLines();
        const new_window_valid: bool = try self.buffer.?.updateBufferWindow(offset_row, &self.ranges.?);
        _ = try self.buffer.?.cacheLines();
        return new_window_valid;
    }

    pub inline fn getStartRelativeLine(self: *@This(), line: usize) *Line {
        return @as(*Line, &self.buffer.?.lines.items[self.ranges.?.lines.start + line]);
    }

    fn drawLine(line: []const u8, y_offset: usize, window: vaxis.Window) !void {
        _ = try window.printSegment(.{
            .text = line,
            .style = .{
                .bg = colours.BLACK,
                .fg = colours.WHITE,
                .reverse = false,
            },
        }, .{
            .row_offset = y_offset,
            .col_offset = 0,
        });
        return;
    }

    pub fn draw(self: *@This()) !void {
        if (self.buffer == null) {
            return;
        } else if (self.buffer.?.tree_sitter != null) {
            try self.buffer.?.tree_sitter.?.drawBuffer(self.window, self.ranges.?.lines);
            return;
        }
        const lines = self.buffer.?.lines.items[self.ranges.?.lines.start..self.ranges.?.lines.end];
        for (lines, 0..) |line, y_offset| {
            try drawLine(line.items, y_offset, self.window);
        }
    }
};
