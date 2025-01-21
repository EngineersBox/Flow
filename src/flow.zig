const std = @import("std");
const vaxis = @import("vaxis");
const Event = @import("event.zig").Event;
const colours = @import("colours.zig");
const nanotime = @import("timer.zig").nanotime;
const fb = @import("buffer.zig");
const FileBuffer = fb.FileBuffer;
const FileBufferIterator = fb.FileBufferIterator;
const Range = fb.Range;
const logToFile = @import("log.zig").logToFile;
const TreeSitter = @import("lang.zig").TreeSitter;
const Config = @import("config.zig");
const zts = @import("zts");

/// Set the default panic handler to the vaxis panic_handler. This will clean up the terminal if any
/// panics occur
pub const panic = vaxis.panic_handler;

/// Set some scope levels for the vaxis scopes
pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .warn },
        .{ .scope = .vaxis_parser, .level = .warn },
    },
};

pub const TextMode = enum(u2) {
    NORMAL = 0,
    INSERT = 1,
    VISUAL = 2,
    COMMAND = 3,

    pub fn toColor(self: TextMode) vaxis.Color {
        return switch (self) {
            TextMode.NORMAL => colours.RED,
            TextMode.INSERT => colours.YELLOW,
            TextMode.VISUAL => colours.MAGENTA,
            TextMode.COMMAND => colours.CYAN,
        };
    }

    pub fn cursorShape(self: TextMode) vaxis.Cell.CursorShape {
        return switch (self) {
            TextMode.NORMAL => vaxis.Cell.CursorShape.block,
            TextMode.INSERT => vaxis.Cell.CursorShape.beam,
            TextMode.VISUAL => vaxis.Cell.CursorShape.block,
            TextMode.COMMAND => vaxis.Cell.CursorShape.block,
        };
    }
};

const ClampMode = enum(u2) { NONE = 0, START = 1, END = 2 };

/// The application state
pub const Flow = struct {
    allocator: std.mem.Allocator,
    config: Config,
    tab_spaces_buffer: []u8,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    buffer: FileBuffer,
    mode: TextMode,
    cursor_blink_ns: u64,
    previous_draw: u64,
    window_lines: std.ArrayList(std.ArrayList(u8)),
    tree_sitter: ?TreeSitter,
    cursor_offset: usize,
    needs_reparse: bool,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Flow {
        var extension: []const u8 = std.fs.path.extension(file_path);
        extension = std.mem.trimLeft(u8, extension, ".");
        const config = Config.default;
        const tab_spaces_buffer = try allocator.alloc(u8, config.spaces_per_tab);
        @memset(tab_spaces_buffer, @as(u8, @intCast(' ')));
        return .{
            .allocator = allocator,
            .config = config,
            .tab_spaces_buffer = tab_spaces_buffer,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .buffer = try FileBuffer.initFromFile(allocator, file_path),
            .mode = TextMode.NORMAL,
            .cursor_blink_ns = 8 * std.time.ns_per_ms,
            .previous_draw = 0,
            .window_lines = std.ArrayList(std.ArrayList(u8)).init(allocator),
            .tree_sitter = try TreeSitter.initFromFileExtension(allocator, extension),
            .cursor_offset = 0,
            .needs_reparse = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buffer.deinit();
        for (self.window_lines.items) |line| {
            line.deinit();
        }
        self.window_lines.deinit();
        self.allocator.free(self.tab_spaces_buffer);
    }

    pub fn run(self: *@This()) !void {
        // Initialize our event loop. This particular loop requires intrusive init
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 5 * std.time.ns_per_s);
        try self.vx.setMouseMode(self.tty.anyWriter(), true);
        try self.setBufferWindow(0, @intCast(self.vx.screen.height));
        if (self.tree_sitter != null) {
            // Parse the loaded buffer
            var buffer = std.ArrayList(u8).init(self.allocator);
            var iter = try self.buffer.lineIterator();
            while (try iter.next()) |line| {
                try buffer.appendSlice(line.items);
                line.deinit();
            }
            try self.tree_sitter.?.parseBuffer(buffer.items);
            buffer.deinit();
        }
        while (!self.should_quit) {
            // pollEvent blocks until we have an event
            loop.pollEvent();
            // tryEvent returns events until the queue is empty
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }
            // Draw our application after handling events
            try self.draw();
        }
    }

    fn handleModeNormal(self: *@This(), key: vaxis.Key) !void {
        if (key.matches(';', .{})) {
            self.mode = TextMode.COMMAND;
            return;
        }
        switch (key.codepoint) {
            'i' => self.mode = TextMode.INSERT,
            'h', vaxis.Key.left => {
                try self.shiftCursorCol(-1);
            },
            'j', vaxis.Key.down => {
                try self.shiftCursorRow(1, ClampMode.NONE);
            },
            'k', vaxis.Key.up => {
                try self.shiftCursorRow(-1, ClampMode.NONE);
            },
            'l', vaxis.Key.right => {
                try self.shiftCursorCol(1);
            },
            else => return,
        }
    }

    fn setBufferWindow(self: *@This(), start: usize, height: usize) !void {
        self.clearWindowLines();
        try self.buffer.setBufferWindow(start, height);
        _ = try self.cacheWindowLines();
    }

    fn updateBufferWindow(self: *@This(), offset_row: isize) !bool {
        if (offset_row < 0 and self.buffer.buffer_offset_range_indicies.?.start < @abs(offset_row)) {
            return false;
        } else if (offset_row > 0 and self.buffer.meta.size - 1 - self.buffer.buffer_offset_range_indicies.?.end < @abs(offset_row)) {
            return false;
        }
        self.clearWindowLines();
        const new_window_valid: bool = try self.buffer.updateBufferWindow(offset_row);
        _ = try self.cacheWindowLines();
        return new_window_valid;
    }

    fn clearWindowLines(self: *@This()) void {
        for (self.window_lines.items) |line| {
            line.deinit();
        }
        self.window_lines.clearAndFree();
    }

    /// Returns true when lines are cached, false if cache already exists
    fn cacheWindowLines(self: *@This()) !bool {
        if (self.window_lines.items.len != 0) {
            return false;
        }
        var line_iterator: FileBufferIterator = try self.buffer.lineIterator();
        while (try line_iterator.next()) |line| {
            try self.window_lines.append(line);
        }
        return true;
    }

    inline fn getCurrentLine(self: *@This()) *std.ArrayList(u8) {
        return @as(*std.ArrayList(u8), &self.window_lines.items[self.buffer.buffer_line_range_indicies.?.start + self.vx.screen.cursor_row]);
    }

    inline fn getWindowRelativeLine(self: *@This(), line: usize) *std.ArrayList(u8) {
        return @as(*std.ArrayList(u8), &self.window_lines.items[self.buffer.buffer_line_range_indicies.?.start + line]);
    }

    inline fn confineCursorToCurrentLine(self: *@This(), clamp: ClampMode) void {
        const current_line_editable_end = switch (self.mode) {
            TextMode.INSERT => self.getCurrentLine().items.len -| 1,
            else => self.getCurrentLine().items.len -| 2,
        };
        switch (clamp) {
            ClampMode.NONE => {
                self.vx.screen.cursor_col = @min(self.vx.screen.cursor_col, current_line_editable_end);
            },
            ClampMode.START => {
                self.vx.screen.cursor_col = 0;
            },
            ClampMode.END => {
                self.vx.screen.cursor_col = current_line_editable_end;
            },
        }
    }

    fn shiftCursorCol(self: *@This(), offset_col: isize) !void {
        const line: *const std.ArrayList(u8) = self.getCurrentLine();
        const current_line_end = switch (self.mode) {
            TextMode.INSERT => blk: {
                if (line.items.len == 0) {
                    break :blk 0;
                }
                break :blk line.items.len -| @intFromBool(line.items[0] == '\n');
            },
            else => line.items.len -| 1,
        };
        const last_char: u8 = line.getLast();
        var new_col: isize = @intCast(self.vx.screen.cursor_col);
        new_col += offset_col;
        if (new_col >= 0 and new_col <= current_line_end) {
            // Within line
            if (new_col < current_line_end) {
                self.vx.screen.cursor_col = @intCast(new_col);
                self.cursor_offset = @intCast(@as(isize, @intCast(self.cursor_offset)) + offset_col);
                return;
            } else if (last_char != '\n' or self.cursor_offset >= self.buffer.meta.size - 1) {
                return;
            }
            self.vx.screen.cursor_col = @intCast(new_col);
            self.cursor_offset = @intCast(@as(isize, @intCast(self.cursor_offset)) + offset_col);
            // Column is a newline, skip over it to next row
        } else if (new_col < 0 and self.vx.screen.cursor_row == 0 and self.buffer.buffer_offset_range_indicies.?.start == 0) {
            // Already at start of buffer, cannot move up
            return;
        } else if (new_col >= current_line_end and self.buffer.buffer_offset_range_indicies.?.end == self.buffer.meta.size - 1) {
            // Already at end of buffer, cannot move down
            return;
        }
        var shift_factor: isize = 1;
        var clamp: ClampMode = ClampMode.START;
        // Set to min or max to ensure that shiftCursorRow clamps
        // column to start or end of next line
        if (new_col < 0) {
            shift_factor = -1;
            clamp = ClampMode.END;
        } else if (new_col == 0) {
            clamp = ClampMode.NONE;
        }
        try self.shiftCursorRow(
            shift_factor,
            clamp,
        );
    }

    fn adjustCursorOffset(self: *@This(), prev_row: usize, prev_col: usize) void {
        const new_row = self.vx.screen.cursor_row;
        const new_col = self.vx.screen.cursor_col;
        const new_row_len = self.getWindowRelativeLine(new_row).items.len;
        const prev_row_len = self.getWindowRelativeLine(prev_row).items.len;
        if (new_row > prev_row) {
            self.cursor_offset += (prev_row_len - prev_col) + new_col;
            return;
        } else if (new_row < prev_row) {
            self.cursor_offset -= prev_col + (new_row_len - new_col);
            return;
        }
        self.cursor_offset -|= prev_col;
        self.cursor_offset += new_col;
    }

    fn shiftCursorRow(self: *@This(), offset_row: isize, clamp: ClampMode) !void {
        var new_row: isize = @intCast(self.vx.screen.cursor_row);
        new_row += offset_row;
        if (new_row >= 0 and new_row < self.window_lines.items.len) {
            // Inside window
            const prev_row = self.vx.screen.cursor_row;
            const prev_col = self.vx.screen.cursor_col;
            self.vx.screen.cursor_row = @intCast(new_row);
            self.confineCursorToCurrentLine(clamp);
            self.adjustCursorOffset(prev_row, prev_col);
            return;
        }
        // Outside window
        if (!try self.updateBufferWindow(offset_row)) {
            // New window invalid, moved outside buffer bounds
            return;
        }
        const prev_row = self.vx.screen.cursor_row;
        const prev_col = self.vx.screen.cursor_col;
        self.vx.screen.cursor_row = @intCast(new_row);
        self.confineCursorToCurrentLine(clamp);
        self.adjustCursorOffset(prev_row, prev_col);
    }

    fn handleModeInsert(self: *@This(), key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.enter => {
                try self.buffer.insert(self.cursor_offset, "\n");
                // if (self.tree_sitter) |tree| {
                //     const edit = zts.InputEdit{
                //         .start_point = .{ .column = self.vx.screen.cursor_col, .row = self.buffer.buffer_line_range_indicies.?.start + self.vx.screen.cursor_row },
                //         .start_byte = '\n',
                //     };
                //     tree.tree.?.edit(&edit);
                // }
                self.clearWindowLines();
                _ = try self.cacheWindowLines();
                // Move cursor to start of next row
                try self.shiftCursorRow(1, ClampMode.START);
            },
            vaxis.Key.space...0x7E,
            0x80...0xFF,
            => {
                try self.buffer.insert(self.cursor_offset, &.{@intCast(key.codepoint)});
                const line = self.getCurrentLine();
                try line.insert(self.vx.screen.cursor_col, @intCast(key.codepoint));
                try self.shiftCursorCol(1);
                // self.clearWindowLines();
                // _ = try self.cacheWindowLines();
            },
            vaxis.Key.tab => {
                try self.buffer.insert(self.cursor_offset, self.tab_spaces_buffer);
                const line = self.getCurrentLine();
                try line.insertSlice(self.vx.screen.cursor_col, self.tab_spaces_buffer);
                try self.shiftCursorCol(@intCast(self.config.spaces_per_tab));
            },
            vaxis.Key.delete => {
                if (self.cursor_offset == self.buffer.meta.size - 1) {
                    return;
                }
                // Forward delete
                try self.buffer.delete(self.cursor_offset, 1);
                const line = self.getCurrentLine();
                if (line.items[line.items.len -| 1] != '\n' or self.vx.screen.cursor_col < line.items.len - 1) {
                    _ = line.orderedRemove(self.vx.screen.cursor_col);
                } else {
                    // At end of line, which will merge this line with
                    // then ext. Thus it is easier to just regen window
                    // lines cache
                    self.clearWindowLines();
                    _ = try self.cacheWindowLines();
                }
                try self.shiftCursorCol(0);
            },
            vaxis.Key.backspace => {
                if (self.cursor_offset == 0) {
                    return;
                }
                // Backward delete
                try self.buffer.delete(self.cursor_offset - 1, 1);
                const current_cursor_col = self.vx.screen.cursor_col;
                try self.shiftCursorCol(-1);
                if (current_cursor_col > 0) {
                    const line = self.getCurrentLine();
                    _ = line.orderedRemove(current_cursor_col - 1);
                } else {
                    // TODO: Make this merge the current and previous lines in
                    //       the window lines cache instead of refreshing the
                    //       cache. We should only need to refresh during a visual
                    //       selection delete

                    // At start of line, which will merge this line with
                    // the previous. Thus it is easier to just regen window
                    // lines cache
                    self.clearWindowLines();
                    _ = try self.cacheWindowLines();
                }
            },
            vaxis.Key.left => {
                try self.shiftCursorCol(-1);
            },
            vaxis.Key.right => {
                try self.shiftCursorCol(1);
            },
            vaxis.Key.up => {
                try self.shiftCursorRow(-1, ClampMode.NONE);
            },
            vaxis.Key.down => {
                try self.shiftCursorRow(1, ClampMode.NONE);
            },
            vaxis.Key.escape => {
                self.mode = TextMode.NORMAL;
                self.confineCursorToCurrentLine(ClampMode.NONE);
                self.adjustCursorOffset(self.vx.screen.cursor_row, self.vx.screen.cursor_col);
            },
            else => {
                return;
            },
        }
        self.needs_reparse = true;
    }

    fn handleModeVisual(_: *@This(), _: vaxis.Key) !void {
        // TODO: Implement this
    }

    fn handleModeCommand(self: *@This(), key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            'q' => self.should_quit = true,
            'w' => {
                const current_offset_range: Range = self.buffer.buffer_offset_range_indicies.?;
                const current_index_range: Range = self.buffer.buffer_line_range_indicies.?;
                // Pre-clear to avoid having two entire copies of the lines in the window
                self.clearWindowLines();
                try self.buffer.save();
                self.buffer.buffer_offset_range_indicies = current_offset_range;
                self.buffer.buffer_offset_range_indicies = current_index_range;
                self.mode = TextMode.NORMAL;
            },
            'x' => {
                try self.buffer.save();
                self.should_quit = true;
            },
            else => return,
        }
    }

    /// Update our application state from an event
    pub fn update(self: *@This(), event: Event) !void {
        switch (event) {
            .key_press => |key| try switch (self.mode) {
                TextMode.NORMAL => self.handleModeNormal(key),
                TextMode.INSERT => self.handleModeInsert(key),
                TextMode.VISUAL => self.handleModeVisual(key),
                TextMode.COMMAND => self.handleModeCommand(key),
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
                try self.buffer.setBufferWindow(self.buffer.buffer_line_range_indicies.?.start, ws.rows);
                const offset_opt: ?usize = try self.buffer.cursorOffset(.{ .line = self.vx.screen.cursor_row, .col = self.vx.screen.cursor_col });
                if (offset_opt) |offset| {
                    self.cursor_offset = offset;
                } else {
                    return error.OutOfBounds;
                }
            },
            else => {},
        }
    }

    inline fn lineWidth(line: []const u8, window_width: usize) usize {
        if (line.len > window_width) {
            return window_width;
        } else if (line.len > 1 and std.mem.eql(u8, line[line.len - 1 ..], "\n")) {
            return line.len - 1;
        }
        return line.len;
    }

    fn drawLine(line: []const u8, y_offset: usize, window: vaxis.Window) !void {
        const width: usize = lineWidth(line, window.width);
        const child: vaxis.Window = window.child(.{
            .x_off = 0,
            .y_off = y_offset,
            .width = .{ .limit = width },
            .height = .{ .limit = 1 },
        });
        _ = try child.printSegment(.{ .text = line, .style = .{
            .bg = colours.BLACK,
            .fg = colours.WHITE,
            .reverse = false,
        } }, .{});
        return;
    }

    /// Draw our current state
    pub fn draw(self: *@This()) !void {
        const window: vaxis.Window = self.vx.window();
        window.clear();
        self.vx.setMouseShape(.default);
        // BUG: For some reason, using an if to unwrap an optional
        //      makes it a constant value and not variable (which is
        //      needed here).
        if (self.tree_sitter != null) {
            try self.tree_sitter.?.drawBuffer(&self.window_lines, window, self.buffer.buffer_offset_range_indicies.?.start, 0, 0, self.vx.screen.height, self.buffer.buffer_offset_range_indicies.?.end);
        } else {
            const lines = self.window_lines.items[self.buffer.buffer_line_range_indicies.?.start..self.buffer.buffer_line_range_indicies.?.end];
            for (lines, 0..) |line, y_offset| {
                try drawLine(line.items, y_offset, window);
            }
        }
        const cursor_pos_buffer: []u8 = try std.fmt.allocPrint(self.allocator, "{d} | {d}:{d}", .{ self.cursor_offset, self.vx.screen.cursor_row, self.vx.screen.cursor_col });
        defer self.allocator.free(cursor_pos_buffer);
        const status_bar = window.child(.{
            .x_off = window.width - cursor_pos_buffer.len - 1,
            .y_off = window.height - 1,
            .width = .{ .limit = cursor_pos_buffer.len },
            .height = .{ .limit = 1 },
        });
        _ = try status_bar.printSegment(.{ .text = cursor_pos_buffer, .style = .{} }, .{});
        window.showCursor(self.vx.screen.cursor_col, self.vx.screen.cursor_row);
        window.setCursorShape(self.mode.cursorShape());
        const mode_string = switch (self.mode) {
            TextMode.NORMAL => " NORMAL ",
            TextMode.INSERT => " INSERT ",
            TextMode.VISUAL => " VISUAL ",
            TextMode.COMMAND => " COMMAND ",
        };
        const text_mode: vaxis.Window = window.child(.{
            .x_off = 0,
            .y_off = window.height - 1,
            .width = .{ .limit = 9 },
            .height = .{ .limit = 1 },
        });
        _ = try text_mode.printSegment(.{ .text = mode_string, .style = .{ .bg = self.mode.toColor() } }, .{});
        self.previous_draw = nanotime();
        // It's best to use a buffered writer for the render method. TTY provides one, but you
        // may use your own. The provided bufferedWriter has a buffer size of 4096
        var buffered: std.io.BufferedWriter(4096, std.io.AnyWriter) = self.tty.bufferedWriter();
        // Render the application to the screen
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
};
