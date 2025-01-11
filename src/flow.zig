const std = @import("std");
const vaxis = @import("vaxis");
const Event = @import("event.zig").Event;
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
            TextMode.NORMAL => vaxis.Color{ .rgb = .{ 0xFF, 0x00, 0x00 } },
            TextMode.INSERT => vaxis.Color{ .rgb = .{ 0x00, 0xFF, 0x00 } },
            TextMode.VISUAL => vaxis.Color{ .rgb = .{ 0x00, 0x00, 0xFF } },
            TextMode.COMMAND => vaxis.Color{ .rgb = .{ 0x00, 0xFF, 0xFF } },
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
            .cursor_blink_ns = 2 * std.time.ns_per_ms,
            .previous_draw = 0,
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
        }
    }

    fn handleModeNormal(self: *Flow, key: vaxis.Key) !void {
        if (key.matches(':', .{ .shift = true })) {
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

    // fn writeCharAtPos(self: *Flow, char: u8, col: usize, row: usize) !void {
    //     const row_start = row % self.vx.screen.width;
    // }

    fn handleModeInsert(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
            vaxis.Key.escape => self.mode = TextMode.NORMAL,
            0x20...0x7E => if (self.buffer_init) {
                self.buffer[(self.vx.screen.cursor_row * self.vx.screen.width) + self.vx.screen.cursor_col] = @intCast(key.codepoint);
            },
            else => return,
        }
    }

    fn handleModeVisual(_: *Flow, _: vaxis.Key) !void {
        // TODO: Implement this
    }

    fn handleModeCommand(self: *Flow, key: vaxis.Key) !void {
        switch (key.codepoint) {
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
                    _ = self.allocator.resize(self.buffer, ws.cols * ws.rows);
                } else {
                    std.log.info("H: {} W: {}", .{ ws.cols, ws.rows });
                    self.buffer = try self.allocator.alloc(u8, ws.cols * ws.rows);
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
        // const status = try std.fmt.allocPrint(self.allocator, "{}:{}", .{ self.vx.screen.cursor_col, self.vx.screen.cursor_row });
        // defer self.allocator.free(status);
        // const status_bar = win.child(.{
        //     .x_off = win.width - 7 - 1,
        //     .y_off = win.height - 1,
        //     .width = .{ .limit = 7 },
        //     .height = .{ .limit = 1 },
        // });
        // _ = try status_bar.printSegment(.{ .text = status, .style = .{} }, .{});

        const cursor_blink = nanotime() - self.previous_draw > self.cursor_blink_ns;
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
        var style = vaxis.Style{ .bg = .default };
        if (cursor_blink) {
            style.bg = vaxis.Color{ .rgb = .{ 0xFF, 0xFF, 0xFF } };
        }
        _ = try cursor.printSegment(.{ .text = " ", .style = style }, .{});

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

        // const child = win.child(.{
        //     .x_off = 0,
        //     .y_off = win.height - 1,
        //     .width = .{ .limit = msg.len },
        //     .height = .{ .limit = 1 },
        // });
        //
        // // mouse events are much easier to handle in the draw cycle. Windows have a helper method to
        // // determine if the event occurred in the target window. This method returns null if there
        // // is no mouse event, or if it occurred outside of the window
        // const style: vaxis.Style = if (child.hasMouse(self.mouse)) |_| blk: {
        //     // We handled the mouse event, so set it to null
        //     self.mouse = null;
        //     self.vx.setMouseShape(.pointer);
        //     break :blk .{ .reverse = true };
        // } else .{};
        //
        // // Print a text segment to the screen. This is a helper function which iterates over the
        // // text field for graphemes. Alternatively, you can implement your own print functions and
        // // use the writeCell API.
        // _ = try child.printSegment(.{ .text = msg, .style = style }, .{});
    }
};
