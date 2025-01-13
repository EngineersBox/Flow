const std = @import("std");
const vaxis = @import("vaxis");
const Event = @import("event.zig").Event;
const colours = @import("colours.zig");
const nanotime = @import("timer.zig").nanotime;
const FileBuffer = @import("buffer.zig").FileBuffer;

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

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Flow {
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
        };
    }

    pub fn deinit(self: *Flow) void {
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.buffer.deinit();
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
        try self.buffer.applyBufferWindow(self.vx.screen.height);
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
                if (self.vx.screen.cursor_col > 0) {
                    self.vx.screen.cursor_col -= 1;
                }
            },
            'j', vaxis.Key.down => {
                if (self.vx.screen.cursor_row < self.vx.screen.height - 2) {
                    self.vx.screen.cursor_row += 1;
                }
            },
            'k', vaxis.Key.up => {
                if (self.vx.screen.cursor_row > 0) {
                    self.vx.screen.cursor_row -= 1;
                }
            },
            'l', vaxis.Key.right => {
                if (self.vx.screen.cursor_col < self.vx.screen.width - 1) {
                    self.vx.screen.cursor_col += 1;
                }
            },
            else => return,
        }
    }

    fn handleModeInsert(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            vaxis.Key.tab, vaxis.Key.space...0x7E, 0x80...0xFF => {
                const offset_opt: ?usize = self.buffer.cursorOffset(.{ .line = self.vx.screen.cursor_row, .col = self.vx.screen.cursor_col });
                if (offset_opt) |offset| {
                    try self.buffer.piecetable.insert(offset, &.{@intCast(key.codepoint)});
                }
            },
            vaxis.Key.delete, vaxis.Key.backspace => {
                const offset: ?usize = self.buffer.cursorOffset(.{ .line = self.vx.screen.cursor_row, .col = self.vx.screen.cursor_col });
                if (offset == null) {
                    return;
                } else if (key.codepoint == vaxis.Key.delete) {
                    // Forward delete
                    try self.buffer.piecetable.delete(offset.?, 1);
                    return;
                } else if (self.vx.screen.cursor_col > 0) {
                    // Backward delete
                    try self.buffer.piecetable.delete(offset.? - 1, 1);
                }
            },
            vaxis.Key.left => {
                if (self.vx.screen.cursor_col > 0) {
                    self.vx.screen.cursor_col -= 1;
                }
            },
            vaxis.Key.down => {
                if (self.vx.screen.cursor_row < self.vx.screen.height - 2) {
                    self.vx.screen.cursor_row += 1;
                }
            },
            vaxis.Key.up => {
                if (self.vx.screen.cursor_row > 0) {
                    self.vx.screen.cursor_row -= 1;
                }
            },
            vaxis.Key.right => {
                if (self.vx.screen.cursor_col < self.vx.screen.width - 1) {
                    // TODO: Check if next char is a newline,
                    //       if so move to first col in next row
                    self.vx.screen.cursor_col += 1;
                }
            },
            else => {},
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
                try self.buffer.save();
                try self.buffer.applyBufferWindow(self.vx.screen.height);
                try self.buffer.updateBufferWindow(@intCast(self.vx.screen.cursor_row));
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

    /// Draw our current state
    pub fn draw(self: *Flow) !void {
        const win = self.vx.window();
        win.clear();
        self.vx.setMouseShape(.default);
        var iterator = try self.buffer.lineIterator();
        var y_offset: usize = 0;
        while (try iterator.next()) |line| : (y_offset += 1) {
            const child = win.child(.{
                .x_off = 0,
                .y_off = y_offset,
                .width = .{ .limit = win.width },
                .height = .{ .limit = 1 },
            });
            _ = try child.printSegment(.{ .text = line.items, .style = .{
                .bg = colours.BLACK,
                .fg = colours.WHITE,
                .reverse = false,
            } }, .{});
            defer line.deinit();
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
