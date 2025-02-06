const std = @import("std");
const vaxis = @import("vaxis");
const ts = @import("tree-sitter");

const Event = @import("event.zig").Event;
const colours = @import("colours.zig");
const nanotime = @import("timer.zig").nanotime;
const b = @import("buffer/buffer.zig");
const Buffer = b.Buffer;
const BufferIterator = b.BufferIterator;
const Line = b.Line;
const _ranges = @import("window/range.zig");
const Range = _ranges.Range;
const Position = _ranges.Position;
const WindowRanges = _ranges.WindowRanges;
const Window = @import("window/window.zig").Window;
const TreeSitter = @import("lang/tree_sitter.zig").TreeSitter;
const Config = @import("config.zig").Config;

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
    buffer: *Buffer,
    active_window: ?Window,
    mode: TextMode,
    cursor_blink_ns: u64,
    previous_draw: u64,
    cursor_offset: usize,
    needs_reparse: bool,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Flow {
        const config: Config = try Config.init(allocator);
        const tab_spaces_buffer: []u8 = try allocator.alloc(u8, config.properties.value.spaces_per_tab);
        @memset(tab_spaces_buffer, @as(u8, @intCast(' ')));
        const buffer: *Buffer = try allocator.create(Buffer);
        buffer.* = try Buffer.initFromFile(allocator, config, file_path);
        return .{
            .allocator = allocator,
            .config = config,
            .tab_spaces_buffer = tab_spaces_buffer,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null, // TODO: Create and handle mouse
            .buffer = buffer,
            .active_window = null,
            .mode = TextMode.NORMAL,
            .cursor_blink_ns = 8 * std.time.ns_per_ms,
            .previous_draw = 0,
            .cursor_offset = 0,
            .needs_reparse = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        if (self.active_window) |*window| {
            if (window.*.buffer) |*buf| {
                buf.*.deinit();
            }
            window.deinit();
        }
        self.buffer.deinit();
        self.allocator.free(self.tab_spaces_buffer);
        self.config.deinit();
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
        while (self.vx.screen.height == 0) {
            loop.pollEvent();
            if (loop.tryEvent()) |event| {
                try self.update(event);
            }
        }
        self.active_window = Window.init(self.vx.window().child(.{}));
        try self.active_window.?.bindBuffer(self.buffer);
        try self.active_window.?.setBufferWindow(0, @intCast(self.vx.screen.height - 1));
        try self.buffer.parseIntoTreeSitter();
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

    inline fn getCurrentLine(self: *@This()) *Line {
        return self.active_window.?.getStartRelativeLine(self.vx.screen.cursor_row);
    }

    inline fn confineCursorToCurrentLine(self: *@This(), clamp_mode: ClampMode) void {
        const current_line_editable_end = switch (self.mode) {
            TextMode.INSERT => self.getCurrentLine().items.len -| 1,
            else => self.getCurrentLine().items.len -| 2,
        };
        switch (clamp_mode) {
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
        const line: *const Line = self.getCurrentLine();
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
        } else if (new_col < 0 and self.vx.screen.cursor_row == 0 and self.active_window.?.ranges.?.offset.start == 0) {
            // Already at start of buffer, cannot move up
            return;
        } else if (new_col >= current_line_end and self.active_window.?.ranges.?.offset.end == self.buffer.meta.size - 1) {
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
        const new_row: usize = self.vx.screen.cursor_row;
        const new_col: usize = self.vx.screen.cursor_col;
        const new_row_len: usize = self.active_window.?.getStartRelativeLine(new_row).items.len;
        const prev_row_len: usize = self.active_window.?.getStartRelativeLine(prev_row).items.len;
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

    fn shiftCursorRow(self: *@This(), offset_row: isize, clamp_mode: ClampMode) !void {
        var new_row: isize = @intCast(self.vx.screen.cursor_row);
        new_row += offset_row;
        if (new_row >= 0 and new_row < self.active_window.?.buffer.?.lines.items.len) {
            // Inside window
            const prev_row: usize = self.vx.screen.cursor_row;
            const prev_col: usize = self.vx.screen.cursor_col;
            self.vx.screen.cursor_row = @intCast(new_row);
            self.confineCursorToCurrentLine(clamp_mode);
            self.adjustCursorOffset(prev_row, prev_col);
            return;
        }
        // Outside window
        if (!try self.active_window.?.updateBufferWindow(offset_row)) {
            // New window invalid, moved outside buffer bounds
            return;
        }
        const prev_row: usize = self.vx.screen.cursor_row;
        const prev_col: usize = self.vx.screen.cursor_col;
        self.vx.screen.cursor_row = @intCast(new_row);
        self.confineCursorToCurrentLine(clamp_mode);
        self.adjustCursorOffset(prev_row, prev_col);
    }

    fn modifyCharAtCursorInTS(self: *@This(), new_cursor: Position, previous_cursor: Position, comptime adjustment: isize) !void {
        if (self.active_window == null or self.active_window.?.buffer == null or self.active_window.?.buffer.?.tree_sitter == null) {
            return;
        }
        const tree_sitter: *TreeSitter = &self.active_window.?.buffer.?.tree_sitter.?;
        const target_node: ?ts.Node = tree_sitter.tree.?.rootNode().descendantForPointRange(
            .{
                .column = @intCast(new_cursor.col),
                .row = @intCast(new_cursor.line),
            },
            .{
                .column = @intCast(previous_cursor.col),
                .row = @intCast(previous_cursor.line),
            },
        );
        if (target_node == null) {
            std.log.err(
                "No target node in range ({d},{d}) to ({d},{d})",
                .{
                    new_cursor.col,
                    new_cursor.line,
                    previous_cursor.col,
                    previous_cursor.line,
                },
            );
            return;
        }
        // TODO: Handle the case when we delete the last char in a node
        const end_point: ts.Point = target_node.?.endPoint();
        const end_byte: u32 = target_node.?.endByte();
        const edit = ts.InputEdit{
            .start_point = target_node.?.startPoint(),
            .old_end_point = end_point,
            .new_end_point = .{
                .column = @intCast(@as(isize, @intCast(end_point.column)) + adjustment),
                .row = end_point.row,
            },
            .start_byte = target_node.?.startByte(),
            .old_end_byte = end_byte,
            .new_end_byte = @intCast(@as(isize, @intCast(end_byte)) + adjustment),
        };
        tree_sitter.tree.?.edit(edit);
        try self.active_window.?.buffer.?.reprocessRange(.{
            .start = @min(new_cursor.line, previous_cursor.line),
            .end = @max(new_cursor.line, previous_cursor.line),
            .max_diff = null,
        });
    }

    fn handleModeInsert(self: *@This(), key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.enter => {
                try self.active_window.?.buffer.?.insert(self.cursor_offset, "\n", &self.active_window.?.ranges.?);
                self.buffer.clearLines();
                _ = try self.buffer.cacheLines();
                // Move cursor to start of next row
                try self.shiftCursorRow(1, ClampMode.START);
            },
            vaxis.Key.space...0x7E,
            0x80...0xFF,
            => {
                try self.active_window.?.buffer.?.insert(
                    self.cursor_offset,
                    if (key.text) |text| text else &.{@intCast(key.codepoint)},
                    &self.active_window.?.ranges.?,
                );
                const line: *Line = self.getCurrentLine();
                try line.insert(self.vx.screen.cursor_col, @intCast(key.codepoint));
                const cursor_position: Position = .{
                    .col = self.vx.screen.cursor_col,
                    .line = self.vx.screen.cursor_row,
                };
                try self.modifyCharAtCursorInTS(cursor_position, cursor_position, 1);
                try self.shiftCursorCol(1);
                // self.buffer.clearLines();
                // _ = try self.buffer.cacheLines();
            },
            vaxis.Key.tab => {
                try self.active_window.?.buffer.?.insert(self.cursor_offset, self.tab_spaces_buffer, &self.active_window.?.ranges.?);
                const line: *Line = self.getCurrentLine();
                try line.insertSlice(self.vx.screen.cursor_col, self.tab_spaces_buffer);
                try self.shiftCursorCol(@intCast(self.config.properties.value.spaces_per_tab));
            },
            vaxis.Key.delete => {
                if (self.cursor_offset == self.buffer.meta.size - 1) {
                    return;
                }
                // Forward delete
                try self.active_window.?.buffer.?.delete(self.cursor_offset, 1, &self.active_window.?.ranges.?);
                const line: *Line = self.getCurrentLine();
                if (line.items[line.items.len -| 1] != '\n' or self.vx.screen.cursor_col < line.items.len - 1) {
                    _ = line.orderedRemove(self.vx.screen.cursor_col);
                } else {
                    // At end of line, which will merge this line with
                    // then next. Thus it is easier to just regen window
                    // lines cache
                    // self.buffer.clearLines();
                    // _ = try self.buffer.cacheLines();
                    var current_line: *Line = self.getCurrentLine();
                    _ = current_line.orderedRemove(current_line.items.len - 1);
                    const next_line: Line = self.active_window.?.buffer.?.lines.orderedRemove(self.active_window.?.ranges.?.lines.start + self.vx.screen.cursor_row + 1);
                    defer next_line.deinit();
                    try current_line.appendSlice(next_line.items);
                }
                const previous_cursor: Position = .{
                    .col = self.vx.screen.cursor_col,
                    .line = self.vx.screen.cursor_row,
                };
                try self.shiftCursorCol(0);
                const new_cursor: Position = .{
                    .col = self.vx.screen.cursor_col,
                    .line = self.vx.screen.cursor_row,
                };
                // Update TS after as we can rely on the cursor position
                // position calculations to correctly remove the character
                // at the start of end of a line
                try self.modifyCharAtCursorInTS(new_cursor, previous_cursor, -1);
            },
            vaxis.Key.backspace => {
                if (self.cursor_offset == 0) {
                    return;
                }
                // Backward delete
                const previous_cursor: Position = .{
                    .col = self.vx.screen.cursor_col,
                    .line = self.vx.screen.cursor_row,
                };
                try self.active_window.?.buffer.?.delete(self.cursor_offset - 1, 1, &self.active_window.?.ranges.?);
                const current_cursor_col = self.vx.screen.cursor_col;
                try self.shiftCursorCol(-1);
                const new_cursor: Position = .{
                    .col = self.vx.screen.cursor_col,
                    .line = self.vx.screen.cursor_row,
                };
                if (current_cursor_col > 0) {
                    const line: *Line = self.getCurrentLine();
                    _ = line.orderedRemove(current_cursor_col - 1);
                } else {
                    // TODO: Make this merge the current and previous lines in
                    //       the window lines cache instead of refreshing the
                    //       cache. We should only need to refresh during a visual
                    //       selection delete

                    // At start of line, which will merge this line with
                    // the previous. Thus it is easier to just regen window
                    // lines cache
                    // self.buffer.clearLines();
                    // _ = try self.buffer.cacheLines();
                    var current_line: *Line = self.getCurrentLine();
                    _ = current_line.orderedRemove(current_line.items.len - 1);
                    const next_line: Line = self.active_window.?.buffer.?.lines.orderedRemove(self.active_window.?.ranges.?.lines.start + self.vx.screen.cursor_row + 1);
                    defer next_line.deinit();
                    try current_line.appendSlice(next_line.items);
                }
                // Update TS after as we can rely on the cursor position
                // position calculations to correctly remove the character
                // at the start of end of a line
                try self.modifyCharAtCursorInTS(new_cursor, previous_cursor, -1);
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
                const ranges: ?WindowRanges = self.active_window.?.ranges;
                // Pre-clear to avoid having two entire copies of the lines in the window
                self.active_window.?.buffer.?.clearLines();
                try self.active_window.?.buffer.?.save();
                self.active_window.?.ranges = ranges;
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
                if (self.active_window == null or self.active_window.?.buffer == null) {
                    return;
                }
                const start: usize = if (self.active_window.?.ranges) |r| r.lines.start else 0;
                self.active_window.?.ranges = try self.active_window.?.buffer.?.setBufferWindow(
                    start,
                    ws.rows,
                );
                const offset_opt: ?usize = self.active_window.?.buffer.?.cursorOffset(
                    .{
                        .line = self.vx.screen.cursor_row,
                        .col = self.vx.screen.cursor_col,
                    },
                    &self.active_window.?.ranges.?,
                );
                if (offset_opt) |offset| {
                    self.cursor_offset = offset;
                } else {
                    return error.OutOfBounds;
                }
            },
            else => {},
        }
    }

    /// Draw our current state
    pub fn draw(self: *@This()) !void {
        const window: vaxis.Window = self.vx.window();
        window.clear();
        self.vx.setMouseShape(.default);
        if (self.active_window) |*active_window| {
            try active_window.*.draw();
        }
        const cursor_pos_buffer: []u8 = try std.fmt.allocPrint(
            self.allocator,
            "{d} | {d}:{d}",
            .{
                self.cursor_offset,
                self.vx.screen.cursor_row,
                self.vx.screen.cursor_col,
            },
        );
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
