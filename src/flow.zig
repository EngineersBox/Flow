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
};

/// The application state
pub const Flow = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    mouse: ?vaxis.Mouse,
    buffer: FileBuffer,
    mode: TextMode,
    cursor_blink_ns: u64,
    previous_draw: u64,
    window_lines: std.ArrayList(std.ArrayList(u8)),
    total_line_count: usize,
    tree_sitter: ?TreeSitter,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Flow {
        var extension = std.fs.path.extension(file_path);
        extension = std.mem.trimLeft(u8, extension, ".");
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .buffer = try FileBuffer.init(allocator, file_path),
            .mode = TextMode.NORMAL,
            .cursor_blink_ns = 8 * std.time.ns_per_ms,
            .previous_draw = 0,
            .window_lines = std.ArrayList(std.ArrayList(u8)).init(allocator),
            .total_line_count = 0,
            .tree_sitter = try TreeSitter.initFromFileExtension(extension),
        };
    }

    pub fn deinit(self: *Flow) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buffer.deinit();
        for (self.window_lines.items) |line| {
            line.deinit();
        }
        self.window_lines.deinit();
    }

    pub fn run(self: *Flow) !void {
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
        self.total_line_count = self.buffer.file_buffer.len;
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

    fn handleModeNormal(self: *Flow, key: vaxis.Key) !void {
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
                try self.shiftCursorRow(1);
            },
            'k', vaxis.Key.up => {
                try self.shiftCursorRow(-1);
            },
            'l', vaxis.Key.right => {
                try self.shiftCursorCol(1);
            },
            else => return,
        }
    }

    fn setBufferWindow(self: *Flow, start: usize, height: usize) !void {
        self.clearWindowLines();
        try self.buffer.setBufferWindow(start, height);
        _ = try self.cacheWindowLines();
    }

    fn updateBufferWindow(self: *Flow, offset_row: isize) !bool {
        self.clearWindowLines();
        const new_window_valid = try self.buffer.updateBufferWindow(offset_row);
        _ = try self.cacheWindowLines();
        return new_window_valid;
    }

    fn clearWindowLines(self: *Flow) void {
        for (self.window_lines.items) |line| {
            line.deinit();
        }
        self.window_lines.clearAndFree();
    }

    /// Returns true when lines are cached, false if cache already exists
    fn cacheWindowLines(self: *Flow) !bool {
        if (self.window_lines.items.len != 0) {
            return false;
        }
        var line_iterator = try self.buffer.lineIterator();
        while (try line_iterator.next()) |line| {
            try self.window_lines.append(line);
        }
        return true;
    }

    inline fn confineCursorToCurrentLine(self: *Flow) void {
        self.vx.screen.cursor_col = @min(self.vx.screen.cursor_col, self.window_lines.items[self.vx.screen.cursor_row].items.len);
    }

    fn shiftCursorCol(self: *Flow, offset_col: isize) !void {
        const line: *const std.ArrayList(u8) = &self.window_lines.items[self.vx.screen.cursor_row];
        var new_col: isize = @intCast(self.vx.screen.cursor_col);
        new_col += offset_col;
        if (new_col >= 0 and new_col < line.*.items.len) {
            // Within line
            self.vx.screen.cursor_col = @intCast(new_col);
            return;
        }
        var shift_factor: isize = 1;
        if (new_col < 0) {
            shift_factor = -1;
        }
        try self.shiftCursorRow(shift_factor);
    }

    fn shiftCursorRow(self: *Flow, offset_row: isize) !void {
        var new_row: isize = @intCast(self.vx.screen.cursor_row);
        new_row += offset_row;
        if (new_row >= 0 and new_row < self.window_lines.items.len) {
            // Inside window
            self.vx.screen.cursor_row = @intCast(new_row);
            self.confineCursorToCurrentLine();
            return;
        }
        // Outside window
        if (!try self.updateBufferWindow(offset_row)) {
            // New window invalid, moved outside buffer bounds
            return;
        }
        self.vx.screen.cursor_row = @intCast(new_row);
        self.confineCursorToCurrentLine();
    }

    fn handleModeInsert(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            vaxis.Key.tab, vaxis.Key.space...0x7E, 0x80...0xFF, 0x0A, 0x0D => {
                if (key.codepoint == 0x0A or key.codepoint == 0x0D) {
                    self.total_line_count += 1;
                }
                const offset_opt: ?usize = try self.buffer.cursorOffset(.{ .line = self.vx.screen.cursor_row, .col = self.vx.screen.cursor_col });
                if (offset_opt) |offset| {
                    try self.buffer.piecetable.insert(offset, &.{@intCast(key.codepoint)});
                    try self.shiftCursorCol(1);
                    self.clearWindowLines();
                    _ = try self.cacheWindowLines();
                }
            },
            vaxis.Key.delete, vaxis.Key.backspace => {
                const offset: ?usize = try self.buffer.cursorOffset(.{ .line = self.vx.screen.cursor_row, .col = self.vx.screen.cursor_col });
                if (offset == null) {
                    return;
                } else if (key.codepoint == vaxis.Key.delete) {
                    // Forward delete
                    try self.buffer.piecetable.delete(offset.?, 1);
                    try self.shiftCursorCol(0);
                    self.clearWindowLines();
                    _ = try self.cacheWindowLines();
                    // TODO: Update total_line_count
                } else if (self.vx.screen.cursor_col > 0) {
                    // Backward delete
                    try self.buffer.piecetable.delete(offset.? - 1, 1);
                    try self.shiftCursorCol(-1);
                    self.clearWindowLines();
                    _ = try self.cacheWindowLines();
                    // TODO: Update total_line_count
                }
            },
            vaxis.Key.left => {
                try self.shiftCursorCol(-1);
            },
            vaxis.Key.right => {
                try self.shiftCursorCol(1);
            },
            vaxis.Key.up => {
                try self.shiftCursorRow(-1);
            },
            vaxis.Key.down => {
                try self.shiftCursorRow(1);
            },
            else => {
                return;
            },
        }
    }

    fn handleModeVisual(_: *Flow, _: vaxis.Key) !void {
        // TODO: Implement this
    }

    fn handleModeCommand(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            'q' => self.should_quit = true,
            'w' => {
                const current_buffer_window: Range = self.buffer.buffer_line_range_indicies.?;
                // Pre-clear to avoid having two entire copies of the lines in the window
                self.clearWindowLines();
                try self.buffer.save();
                _ = try self.updateBufferWindow(0);
                self.buffer.buffer_line_range_indicies = current_buffer_window;
                self.total_line_count = self.buffer.file_buffer.len;
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
    pub fn update(self: *Flow, event: Event) !void {
        switch (event) {
            .key_press => |key| try switch (self.mode) {
                .NORMAL => self.handleModeNormal(key),
                .INSERT => self.handleModeInsert(key),
                .VISUAL => self.handleModeVisual(key),
                .COMMAND => self.handleModeCommand(key),
            },
            .mouse => |mouse| self.mouse = mouse,
            .winsize => |ws| {
                try self.vx.resize(self.allocator, self.tty.anyWriter(), ws);
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

    fn drawLine(self: *Flow, line: []const u8, y_offset: usize, window: vaxis.Window) !void {
        if (self.tree_sitter == null) {
            const width = lineWidth(line, window.width);
            const child = window.child(.{
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
        try self.tree_sitter.?.parseBuffer(line);
        _ = self.tree_sitter.?.tree.?.rootNode();
    }

    /// Draw our current state
    pub fn draw(self: *Flow) !void {
        const win = self.vx.window();
        win.clear();
        self.vx.setMouseShape(.default);
        for (self.window_lines.items, 0..) |line, y_offset| {
            try self.drawLine(line, y_offset, win);
        }
        const cursor_pos_buffer: []u8 = try std.fmt.allocPrint(self.allocator, "{d}:{d}", .{ self.vx.screen.cursor_col, self.vx.screen.cursor_row });
        defer self.allocator.free(cursor_pos_buffer);
        const status_bar = win.child(.{
            .x_off = win.width - cursor_pos_buffer.len - 1,
            .y_off = win.height - 1,
            .width = .{ .limit = cursor_pos_buffer.len },
            .height = .{ .limit = 1 },
        });
        _ = try status_bar.printSegment(.{ .text = cursor_pos_buffer, .style = .{} }, .{});
        const cursor = win.child(.{
            .x_off = self.vx.screen.cursor_col,
            .y_off = self.vx.screen.cursor_row,
            .width = .{
                .limit = 1,
            },
            .height = .{
                .limit = 1,
            },
        });
        const cursor_index = (self.vx.screen.cursor_row * win.width) + self.vx.screen.cursor_col;
        const cursor_value: u8 = self.buffer.piecetable.get(cursor_index) catch ' ';
        _ = try cursor.printSegment(.{ .text = &.{cursor_value}, .style = .{ .reverse = true } }, .{});
        const mode_string = switch (self.mode) {
            TextMode.NORMAL => " NORMAL ",
            TextMode.INSERT => " INSERT ",
            TextMode.VISUAL => " VISUAL ",
            TextMode.COMMAND => " COMMAND ",
        };
        const text_mode = win.child(.{
            .x_off = 0,
            .y_off = win.height - 1,
            .width = .{ .limit = 9 },
            .height = .{ .limit = 1 },
        });
        _ = try text_mode.printSegment(.{ .text = mode_string, .style = .{ .bg = self.mode.toColor() } }, .{});
        self.previous_draw = nanotime();
        // It's best to use a buffered writer for the render method. TTY provides one, but you
        // may use your own. The provided bufferedWriter has a buffer size of 4096
        var buffered = self.tty.bufferedWriter();
        // Render the application to the screen
        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
};
