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
    max_diff: ?usize,

    pub inline fn hasGrowSpace(self: *@This()) bool {
        return self.max_diff != null and self.end - self.start < self.max_diff.?;
    }

    pub inline fn rangeLeft(self: *@This()) usize {
        if (self.max_diff) {
            return self.max_diff.? -| (self.end - self.start);
        }
        return 0;
    }

    pub inline fn maxEnd(self: *@This()) usize {
        if (self.max_diff) |diff| {
            return self.start + diff;
        }
        return self.end;
    }
};

pub const WindowRanges = struct { offset: Range, lines: Range };
