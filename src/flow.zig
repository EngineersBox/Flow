const std = @import("std");
const vaxis = @import("vaxis");
const Event = @import("event.zig").Event;
const colours = @import("colours.zig");
const nanotime = @import("timer.zig").nanotime;

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
    // A flag for if we should quit
    should_quit: bool,
    /// The tty we are talking to
    tty: vaxis.Tty,
    /// The vaxis instance
    vx: vaxis.Vaxis,
    /// A mouse event that we will handle in the draw cycle
    mouse: ?vaxis.Mouse,
    buffer: []u8,
    buffer_init: bool,
    mode: TextMode,
    cursor_blink_ns: u64,
    previous_draw: u64,
    // NOTE: Needed to outlive the flush call
    cursor_pos_buffer: []u8,

    pub fn init(allocator: std.mem.Allocator) !Flow {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .mouse = null,
            .buffer = undefined,
            .buffer_init = false,
            .mode = TextMode.NORMAL,
            .cursor_blink_ns = 8 * std.time.ns_per_ms,
            .previous_draw = 0,
            .cursor_pos_buffer = undefined,
        };
    }

    pub fn deinit(self: *Flow) void {
        // Deinit takes an optional allocator. You can choose to pass an allocator to clean up
        // memory, or pass null if your application is shutting down and let the OS clean up the
        // memory
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
        self.allocator.free(self.buffer);
    }

    pub fn run(self: *Flow) !void {
        // Initialize our event loop. This particular loop requires intrusive init
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();

        // Start the event loop. Events will now be queued
        try loop.start();

        try self.vx.enterAltScreen(self.tty.anyWriter());

        // Query the terminal to detect advanced features, such as kitty keyboard protocol, etc.
        // This will automatically enable the features in the screen you are in, so you will want to
        // call it after entering the alt screen if you are a full screen application. The second
        // arg is a timeout for the terminal to send responses. Typically the response will be very
        // fast, however it could be slow on ssh connections.
        try self.vx.queryTerminal(self.tty.anyWriter(), 5 * std.time.ns_per_s);

        // Enable mouse events
        try self.vx.setMouseMode(self.tty.anyWriter(), true);

        // This is the main event loop. The basic structure is
        // 1. Handle events
        // 2. Draw application
        // 3. Render
        while (!self.should_quit) {
            // pollEvent blocks until we have an event
            loop.pollEvent();
            // tryEvent returns events until the queue is empty
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }
            // Draw our application after handling events
            try self.draw();
            self.previous_draw = nanotime();

            // It's best to use a buffered writer for the render method. TTY provides one, but you
            // may use your own. The provided bufferedWriter has a buffer size of 4096
            var buffered = self.tty.bufferedWriter();
            // Render the application to the screen
            try self.vx.render(buffered.writer().any());
            try buffered.flush();
            self.allocator.free(self.cursor_pos_buffer);
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

    fn writeCharAtPos(self: *Flow, char: u8, col: usize, row: usize) void {
        const last_pos = ((row + 1) * self.vx.screen.width) - 1;
        const last_row_char: u8 = self.buffer[last_pos];
        if (last_row_char != 0 and last_row_char != vaxis.Key.space and last_row_char != vaxis.Key.tab) {
            // Non-printable characters
            return;
        }
        const pos = (row * self.vx.screen.width) + col;
        if (col >= self.vx.screen.width) {
            return;
        }
        std.mem.copyBackwards(u8, self.buffer[pos + 1 .. last_pos], self.buffer[pos .. last_pos - 1]);
        self.buffer[pos] = char;
        self.vx.screen.cursor_col += 1;
    }

    fn deleteCharAtPos(self: *Flow, remove_ahead: bool, col: usize, row: usize) void {
        const last_pos = ((row + 1) * self.vx.screen.width) - 1;
        const pos = (row * self.vx.screen.width) + col;
        if (remove_ahead and pos != last_pos) {
            std.mem.copyForwards(u8, self.buffer[pos .. last_pos - 1], self.buffer[pos + 1 .. last_pos]);
            self.buffer[last_pos] = 0;
        } else if (!remove_ahead and pos != 0) {
            std.mem.copyForwards(u8, self.buffer[pos - 1 .. last_pos - 1], self.buffer[pos..last_pos]);
            self.buffer[last_pos] = 0;
            self.vx.screen.cursor_col -= 1;
        }
    }

    fn handleModeInsert(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            vaxis.Key.tab, vaxis.Key.space...0x7E, 0x80...0xFF => if (self.buffer_init) {
                self.writeCharAtPos(@intCast(key.codepoint), self.vx.screen.cursor_col, self.vx.screen.cursor_row);
            },
            vaxis.Key.delete, vaxis.Key.backspace => if (self.buffer_init) {
                self.deleteCharAtPos(key.codepoint == vaxis.Key.delete, self.vx.screen.cursor_col, self.vx.screen.cursor_row);
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
                if (self.buffer_init) {
                    _ = self.allocator.resize(self.buffer, ws.cols * (ws.rows - 1));
                } else {
                    self.buffer = try self.allocator.alloc(u8, ws.cols * (ws.rows - 1));
                    @memset(self.buffer, 0);
                    std.mem.copyForwards(u8, self.buffer, "Hello world!");
                    self.buffer_init = true;
                }
            },
            else => {},
        }
    }

    /// Draw our current state
    pub fn draw(self: *Flow) !void {
        // const msg = "Hello, world!";

        // Window is a bounded area with a view to the screen. You cannot draw outside of a windows
        // bounds. They are light structures, not intended to be stored.
        const win = self.vx.window();

        // Clearing the window has the effect of setting each cell to it's "default" state. Vaxis
        // applications typically will be immediate mode, and you will redraw your entire
        // application during the draw cycle.
        win.clear();

        // In addition to clearing our window, we want to clear the mouse shape state since we may
        // be changing that as well
        self.vx.setMouseShape(.default);
        for (0..win.height - 1) |i| {
            const child = win.child(.{
                .x_off = 0,
                .y_off = i,
                .width = .{ .limit = win.width },
                .height = .{ .limit = 1 },
            });
            _ = try child.printSegment(.{ .text = self.buffer[(i * win.height)..((i + 1) * win.height)], .style = .{} }, .{});
        }
        self.cursor_pos_buffer = try std.fmt.allocPrint(self.allocator, "{d}:{d}", .{ self.vx.screen.cursor_col, self.vx.screen.cursor_row });
        const status_bar = win.child(.{
            .x_off = win.width - self.cursor_pos_buffer.len - 1,
            .y_off = win.height - 1,
            .width = .{ .limit = self.cursor_pos_buffer.len },
            .height = .{ .limit = 1 },
        });
        _ = try status_bar.printSegment(.{ .text = self.cursor_pos_buffer, .style = .{} }, .{});

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
        const style: vaxis.Style = vaxis.Style{
            .reverse = true,
        };
        const cursor_index = (self.vx.screen.cursor_row * win.width) + self.vx.screen.cursor_col;
        var cursor_value: []u8 = self.buffer[cursor_index .. cursor_index + 1];
        if (cursor_value[0] == 0) {
            // Need a printable character to change the style colours for some reason
            cursor_value[0] = ' ';
        }
        _ = try cursor.printSegment(.{ .text = cursor_value, .style = style }, .{});

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
    }
};
