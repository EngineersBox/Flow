const std = @import("std");
const ts = @import("tree-sitter");
const vaxis = @import("vaxis");
const json = @import("json");
const Pool = @import("zap");
const known_folders = @import("known-folders");

const colours = @import("../colours.zig");
const Tag = @import("query.zig").Tag;
const Tags = @import("query.zig").Tags;
const Query = @import("query.zig").Query;
const Queries = @import("query.zig").Queries;
const Config = @import("../config.zig").Config;
const TREE_SITTER_QUERIES_PATH = @import("../config.zig").TREE_SITTER_QUERIES_PATH;
const _ranges = @import("../window/range.zig");
const Range = _ranges.Range;
const ConcurrentArrayList = @import("../containers/concurrent_array_list.zig").ConcurrentArrayList;
const ConcurrentStringHashMap = @import("../containers/concurrent_string_hash_map.zig").ConcurrentStringHashMap;
const ConcurrentArrayHashMap = @import("../containers/concurrent_array_hash_map.zig").ConcurrentArrayHashMap;
const lang = @import("lang.zig");

pub const TreeIterator = struct {
    cursor: ts.TreeCursor,
    vistied_children: bool,
    yielded: bool,

    pub fn init(node: ts.Node) TreeIterator {
        return .{
            .cursor = node.walk(),
            .vistied_children = false,
            .yielded = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.cursor.destroy();
    }

    pub fn next(self: *@This()) ?ts.Node {
        while (true) {
            if (self.yielded) {
                self.yielded = false;
                if (!self.cursor.gotoFirstChild()) {
                    self.vistied_children = true;
                }
                continue;
            }
            if (!self.vistied_children) {
                self.yielded = true;
                return self.cursor.node();
            } else if (self.cursor.gotoNextSibling()) {
                self.vistied_children = false;
            } else if (!self.cursor.gotoParent()) {
                break;
            }
        }
        return null;
    }
};

const file_extension_languages = std.StaticStringMap(lang.LanguageGrammar).initComptime(.{
    // .{ "sh", lang.LanguageGrammar.bash },
    // .{ "c", lang.LanguageGrammar.c },
    // .{ "h", lang.LanguageGrammar.c },
    // .{ "css", lang.LanguageGrammar.css },
    // .{ "cpp", lang.LanguageGrammar.cpp },
    // .{ "c++", lang.LanguageGrammar.cpp },
    // .{ "cc", lang.LanguageGrammar.cpp },
    // .{ "hpp", lang.LanguageGrammar.cpp },
    // .{ "h++", lang.LanguageGrammar.cpp },
    // .{ "cs", lang.LanguageGrammar.c_sharp },
    // .{ "ex", lang.LanguageGrammar.elixir },
    // .{ "exs", lang.LanguageGrammar.elixir },
    // .{ "elm", lang.LanguageGrammar.elm },
    // .{ "erl", lang.LanguageGrammar.erlang },
    // .{ "hrl", lang.LanguageGrammar.erlang },
    // .{ "fs", lang.LanguageGrammar.fsharp },
    // .{ "fsi", lang.LanguageGrammar.fsharp },
    // .{ "fsx", lang.LanguageGrammar.fsharp },
    // .{ "fsscript", lang.LanguageGrammar.fsharp },
    // .{ "go", lang.LanguageGrammar.go },
    // .{ "hs", lang.LanguageGrammar.haskell },
    // .{ "lhs", lang.LanguageGrammar.haskell },
    // .{ "java", lang.LanguageGrammar.java },
    // .{ "js", lang.LanguageGrammar.javascript },
    // .{ "cjs", lang.LanguageGrammar.javascript },
    // .{ "mjs", lang.LanguageGrammar.javascript },
    // .{ "jsx", lang.LanguageGrammar.javascript },
    // .{ "json", lang.LanguageGrammar.json },
    // .{ "jl", lang.LanguageGrammar.julia },
    // .{ "kt", lang.LanguageGrammar.kotlin },
    // .{ "kts", lang.LanguageGrammar.kotlin },
    // .{ "kexe", lang.LanguageGrammar.kotlin },
    // .{ "klib", lang.LanguageGrammar.kotlin },
    // .{ "lua", lang.LanguageGrammar.lua },
    // .{ "md", lang.LanguageGrammar.markdown },
    // .{ "nim", lang.LanguageGrammar.nim },
    // .{ "nims", lang.LanguageGrammar.nim },
    // .{ "nimble", lang.LanguageGrammar.nim },
    // .{ "ml", lang.LanguageGrammar.ocaml },
    // .{ "mli", lang.LanguageGrammar.ocaml },
    // .{ "perl", lang.LanguageGrammar.perl },
    // .{ "plx", lang.LanguageGrammar.perl },
    // .{ "pls", lang.LanguageGrammar.perl },
    // .{ "pl", lang.LanguageGrammar.perl },
    // .{ "pm", lang.LanguageGrammar.perl },
    // .{ "xs", lang.LanguageGrammar.perl },
    // .{ "t", lang.LanguageGrammar.perl },
    // .{ "pod", lang.LanguageGrammar.perl },
    // .{ "cgi", lang.LanguageGrammar.perl },
    // .{ "psgi", lang.LanguageGrammar.perl },
    // .{ "php", lang.LanguageGrammar.php },
    // .{ "py", lang.LanguageGrammar.python },
    // .{ "pyc", lang.LanguageGrammar.python },
    // .{ "rb", lang.LanguageGrammar.ruby },
    // .{ "rs", lang.LanguageGrammar.rust },
    // .{ "scala", lang.LanguageGrammar.scala },
    // .{ "sc", lang.LanguageGrammar.scala },
    // .{ "toml", lang.LanguageGrammar.toml },
    // .{ "ts", lang.LanguageGrammar.typescript },
    // .{ "tsx", lang.LanguageGrammar.typescript },
    .{ "zig", lang.LanguageGrammar.zig },
    .{ "zon", lang.LanguageGrammar.zig },
});

fn loadGrammar(grammar: lang.LanguageGrammar) !*const ts.Language {
    inline for (@typeInfo(lang.LanguageGrammar).Enum.fields) |field| {
        // NOTE: With `inline for` the function gets generated as
        //       a series of `if` statements relying on the optimizer
        //       to convert it to a switch.
        if (field.value == @intFromEnum(grammar)) {
            return try lang.loadLanguage(@as(lang.LanguageGrammar, @enumFromInt(field.value)));
        }
    }
    // NOTE: When using `inline for` the compiler doesn't know that every
    //       possible case has been handled requiring an explicit `unreachable`.
    unreachable;
}

fn loadHighlightQueries(allocator: std.mem.Allocator, grammar: lang.LanguageGrammar) !Queries {
    const config_dir_path: []const u8 = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
    defer allocator.free(config_dir_path);
    const full_path: []u8 = try std.fmt.allocPrint(allocator, "{s}{s}{s}/highlights.scm", .{ config_dir_path, TREE_SITTER_QUERIES_PATH, @tagName(grammar) });
    defer allocator.free(full_path);
    var hl_file: std.fs.File = undefined;
    if (std.fs.openFileAbsolute(full_path, .{ .mode = .read_only })) |file| {
        hl_file = file;
    } else |err| switch (err) {
        error.FileNotFound => {
            std.log.err("Missing queries for language at {s}", .{full_path});
            return err;
        },
        else => return err,
    }
    defer hl_file.close();
    const hl_queries = try hl_file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
    defer allocator.free(hl_queries);
    var queries = Queries.init(allocator, hl_queries);
    try queries.parseQueries();
    return queries;
}

const ThreadHighlights = struct {
    index: usize,
    count: usize,
};

fn partitionHighlights(highlights: []ThreadHighlights, query_count: usize, threads: usize) void {
    const chunk_size = query_count / threads;
    const excess = query_count - (chunk_size * threads);
    for (0..threads) |i| {
        highlights[i].index = 0;
        highlights[i].count = chunk_size;
    }
    for (0..excess) |i| {
        highlights[i].count += 1;
    }
    var total: usize = 0;
    for (0..threads) |i| {
        highlights[i].index = total;
        total += highlights[i].count;
    }
}

const Highlight = struct {
    child_options: vaxis.Window.ChildOptions,
    segment: vaxis.Segment,
    print_options: vaxis.PrintOptions,
};
const Highlights = ConcurrentArrayHashMap(usize, Highlight, std.array_hash_map.AutoContext(usize), true);
const QueryHighlights = ConcurrentStringHashMap(*Highlights);
const LineQueryHighlights = std.ArrayList(*QueryHighlights);

const HighlightsUpdateTask = struct {
    task: Pool.Task = .{ .callback = @This().callback },
    wg: *std.Thread.WaitGroup,
    allocator: std.mem.Allocator,
    old_highlights: *LineQueryHighlights,
    new_highlights: *LineQueryHighlights,
    line_range: Range,
    tasks: []QueryTask,
    done: bool,

    fn callback(task: *Pool.Task) void {
        const self: *@This() = @alignCast(@fieldParentPtr("task", task));
        self.wg.wait();
        for (self.line_range.start..self.line_range.end + 1) |i| {
            const offset_index = i - self.line_range.start;
            const old: *QueryHighlights = @atomicRmw(
                *QueryHighlights,
                &self.old_highlights.items[i],
                std.builtin.AtomicRmwOp.Xchg,
                self.new_highlights.items[offset_index],
                std.builtin.AtomicOrder.acq_rel,
            );
            defer old.deinit();
            var iter = old.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.*.deinit();
            }
        }
        self.new_highlights.deinit();
        self.allocator.destroy(self.new_highlights);
        self.allocator.free(self.tasks);
        self.done = true;
    }
};

const QueryTask = struct {
    task: Pool.Task = .{ .callback = @This().callback },
    wg: *std.Thread.WaitGroup,
    allocator: std.mem.Allocator,
    queries: *const Queries,
    language: *const ts.Language,
    config: *const Config,
    highlights: *LineQueryHighlights,
    highlight_indices: *ThreadHighlights,
    lines: *std.ArrayList(std.ArrayList(u8)),
    line_range: Range,
    buffer_size: usize,
    root: ts.Node,

    fn callback(task: *Pool.Task) void {
        const self: *@This() = @alignCast(@fieldParentPtr("task", task));
        defer self.wg.finish();
        const idx_start: usize = self.highlight_indices.index;
        const idx_end = idx_start + self.highlight_indices.count;
        for (idx_start..idx_end) |i| {
            const query_string: std.ArrayList(u8) = self.queries.elems.keys()[i];
            var tags: ?Tags = self.queries.elems.get(query_string);
            var error_offset: u32 = 0;
            var query: *ts.Query = ts.Query.create(self.language, query_string.items, &error_offset) catch |err| {
                std.log.err("Failed to init query. Error at {d}: {s}", .{ error_offset, @errorName(err) });
                continue;
            };
            defer query.destroy();
            _ = query.startByteForPattern(0);
            _ = query.endByteForPattern(@intCast(query_string.items.len));
            var cursor: *ts.QueryCursor = ts.QueryCursor.create();
            defer cursor.destroy();
            cursor.setByteRange(0, @intCast(self.buffer_size)) catch {
                std.log.err("Failed to set cursor byte range: {d} to {d}", .{ 0, self.buffer_size });
                return;
            };
            cursor.setPointRange(
                .{ .row = @intCast(self.line_range.start), .column = 0 },
                .{ .row = @intCast(self.line_range.end + 1), .column = 0 },
            ) catch {
                std.log.err(
                    "Failed to set cursor point range: ({d},{d}) to ({d},{d})",
                    .{
                        self.line_range.start,
                        0,
                        self.line_range.end + 1,
                        0,
                    },
                );
                return;
            };
            cursor.exec(query, self.root);
            while (cursor.nextMatch()) |match| {
                for (match.captures, 0..) |capture, j| {
                    self.storeHighlight(query_string.items, &tags, capture.node) catch |err| {
                        std.log.err(
                            "Failed to store highlight: {s} :: [Column: {d}] [Line: {d}] [Query: {s}] [Capture: {d}]",
                            .{
                                @errorName(err),
                                capture.node.startPoint().column,
                                capture.node.startPoint().row,
                                query_string.items,
                                j,
                            },
                        );
                    };
                }
                cursor.removeMatch(0);
            }
        }
    }

    fn storeHighlight(self: *@This(), query_string: []const u8, tags: *?Tags, node: ts.Node) !void {
        const start = node.startPoint();
        const end = node.endPoint();
        var style: vaxis.Style = .{};
        var tag: ?Tag = null;
        if (tags.* != null and tags.*.?.items.len > 0) {
            tag = tags.*.?.getLast();
            // std.log.err("HL Tag: {s}", .{tag.?.items});
            const theme_highlight = self.config.theme.get(tag.?.items);
            if (theme_highlight) |hl| {
                style.fg = hl.colour;
                style.bold = hl.bold;
                style.italic = hl.italic;
                if (hl.underline) {
                    style.ul = hl.colour;
                }
            }
        }
        var query_highlights: *QueryHighlights = self.highlights.items[@intCast(start.row - self.line_range.start)];
        query_highlights.rwlock.lock();
        defer query_highlights.rwlock.unlock();
        var highlights: ?*Highlights = query_highlights.map.get(query_string);
        if (highlights == null) {
            highlights = try self.allocator.create(Highlights);
            highlights.?.* = Highlights.init(self.allocator);
            try query_highlights.map.put(query_string, highlights.?);
        }
        highlights.?.rwlock.lock();
        defer highlights.?.rwlock.unlock();
        const current_hl: ?Highlight = highlights.?.map.get(start.column);
        if (current_hl != null and current_hl.?.segment.style.fg == .default) {
            return;
        }
        try highlights.?.map.put(start.column, .{
            .child_options = .{
                .width = .{ .limit = end.column - start.column },
                .height = .{ .limit = @max(1, end.row - start.row) },
            },
            .segment = .{
                .text = self.lines.items[start.row].items[start.column..end.column],
                .style = style,
            },
            .print_options = .{
                .row_offset = start.row,
                .col_offset = start.column,
            },
        });
    }
};

pub const TreeSitter = struct {
    allocator: std.mem.Allocator,
    config: Config,
    language: *const ts.Language,
    parser: *ts.Parser,
    tree: ?*ts.Tree,
    queries: Queries,
    per_thread_highlights: []ThreadHighlights,
    highlights: LineQueryHighlights,
    render_thread_pool: Pool,
    update_tasks: ConcurrentArrayList(*HighlightsUpdateTask),

    pub fn initFromFileExtension(
        allocator: std.mem.Allocator,
        config: Config,
        extension: []const u8,
    ) !?TreeSitter {
        const grammar: lang.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(allocator, config, try loadGrammar(grammar), grammar);
    }

    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
        language: *const ts.Language,
        grammar: lang.LanguageGrammar,
    ) !TreeSitter {
        const parser: *ts.Parser = ts.Parser.create();
        try parser.setLanguage(language);
        var queries: Queries = try loadHighlightQueries(allocator, grammar);
        const query_count: usize = @intCast(queries.elems.count());
        const thread_count: usize = @min(query_count, std.Thread.getCpuCount() catch 1);
        const per_thread_highlights = try allocator.alloc(ThreadHighlights, thread_count);
        partitionHighlights(per_thread_highlights, query_count, thread_count);
        return .{
            .allocator = allocator,
            .config = config,
            .language = language,
            .parser = parser,
            .tree = null,
            .queries = queries,
            .per_thread_highlights = per_thread_highlights,
            .highlights = LineQueryHighlights.init(allocator),
            .render_thread_pool = Pool.init(@max(1, std.Thread.getCpuCount() catch 1)),
            .update_tasks = ConcurrentArrayList(*HighlightsUpdateTask).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parser.destroy();
        self.queries.deinit();
        self.allocator.free(self.per_thread_highlights);
        self.render_thread_pool.deinit();
        for (self.highlights.items) |*hls| {
            var iter = hls.*.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            hls.*.deinit();
            self.allocator.destroy(hls.*);
        }
        self.highlights.deinit();
        self.update_tasks.rwlock.lock();
        for (self.update_tasks.array_list.items) |*task| {
            self.allocator.destroy(task.*);
        }
        self.update_tasks.rwlock.unlock();
        self.update_tasks.deinit();
    }

    pub fn parseBuffer(self: *@This(), buffer: []const u8, lines: *std.ArrayList(std.ArrayList(u8))) !void {
        self.tree = self.parser.parseString(buffer, self.tree) orelse return error.FailedReparse;
        for (self.highlights.items) |*hls| {
            var iter = hls.*.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            hls.*.deinit();
            self.allocator.destroy(hls.*);
        }
        self.highlights.deinit();
        self.highlights = LineQueryHighlights.init(self.allocator);
        for (0..lines.items.len) |_| {
            const hl: *QueryHighlights = try self.allocator.create(QueryHighlights);
            hl.* = QueryHighlights.init(self.allocator);
            try self.highlights.append(hl);
        }
        const root: ts.Node = self.tree.?.rootNodeWithOffset(0, .{
            .row = 0,
            .column = 0,
        });
        const tasks: []QueryTask = try self.allocator.alloc(QueryTask, self.per_thread_highlights.len);
        defer self.allocator.free(tasks);
        var wg: std.Thread.WaitGroup = .{};
        defer wg.wait();
        for (tasks, 0..) |*task, i| {
            wg.start();
            task.* = .{
                .wg = &wg,
                .allocator = self.allocator,
                .queries = &self.queries,
                .language = self.language,
                .config = &self.config,
                .highlights = &self.highlights,
                .highlight_indices = &self.per_thread_highlights[i],
                .lines = lines,
                .line_range = .{
                    .start = 0,
                    .end = lines.items.len -| 1,
                    .max_diff = null,
                },
                .buffer_size = buffer.len,
                .root = root,
            };
            Pool.schedule(&self.render_thread_pool, &task.task);
        }
    }

    fn dummyProgressCallback(_: ts.Parser.State) callconv(.C) bool {
        return true;
    }

    pub fn reprocessRange(
        self: *@This(),
        modified_range_len: usize,
        lines: *std.ArrayList(std.ArrayList(u8)),
        range: Range,
        input: ts.Input,
    ) !void {
        // TODO: Should have a fixed set of threads that each have a queue of tasks to pull from and perform.
        //       A single thread should be responsible for HighlightUpdateTasks to do @atomicRmw exchanges on
        //       the highlight lines. This function should then just push these necessary tasks to the thread
        //       queues.
        const new_highlights: *LineQueryHighlights = try self.allocator.create(LineQueryHighlights);
        new_highlights.* = LineQueryHighlights.init(self.allocator);
        for (range.start..range.end + 1) |_| {
            const hls: *QueryHighlights = try self.allocator.create(QueryHighlights);
            hls.* = QueryHighlights.init(self.allocator);
            try new_highlights.append(hls);
        }
        // NOTE: This is temporary as the Parser.parse method doesn't match the C
        //       function parameters (extra null for some reason).
        self.tree = self.parser.parseWithOptions(
            input,
            self.tree,
            .{
                .payload = null,
                .progress_callback = TreeSitter.dummyProgressCallback,
            },
        ) orelse return error.FailedReparse;
        // self.tree = self.parser.parse(input, self.tree) orelse return error.FailedReparse;
        const root: ts.Node = self.tree.?.rootNodeWithOffset(0, .{
            .row = 0,
            .column = 0,
        });
        const tasks: []QueryTask = try self.allocator.alloc(QueryTask, self.per_thread_highlights.len);
        var wg: *std.Thread.WaitGroup = try self.allocator.create(std.Thread.WaitGroup);
        wg.* = .{};
        for (tasks, 0..) |*task, i| {
            wg.start();
            task.* = .{
                .wg = wg,
                .allocator = self.allocator,
                .queries = &self.queries,
                .language = self.language,
                .config = &self.config,
                .highlights = new_highlights,
                .highlight_indices = &self.per_thread_highlights[i],
                .lines = lines,
                .line_range = range,
                .buffer_size = modified_range_len,
                .root = root,
            };
            Pool.schedule(&self.render_thread_pool, &task.task);
        }
        const update_task: *HighlightsUpdateTask = try self.allocator.create(HighlightsUpdateTask);
        update_task.* = .{
            .wg = wg,
            .allocator = self.allocator,
            .old_highlights = &self.highlights,
            .new_highlights = new_highlights,
            .line_range = range,
            .tasks = tasks,
            .done = false,
        };
        Pool.schedule(&self.render_thread_pool, &update_task.task);
        try self.update_tasks.insert(0, update_task);
    }

    pub fn drawBuffer(self: *@This(), window: vaxis.Window, window_lines_offset: Range) !void {
        // NOTE: If necessary at some stage this can be parallelised, but I doubt
        //       that it will need to be. I also feel like I'm going to look at this
        //       comment in future and say "Wow.. that was dumb".. but yeah.
        for (window_lines_offset.start..window_lines_offset.end) |i| {
            var query_highlights: *QueryHighlights = self.highlights.items[i];
            var iter = query_highlights.iterator();
            while (iter.next()) |entry| {
                var highlights: *Highlights = entry.value_ptr.*;
                var hl_iter = highlights.iterator();
                while (hl_iter.next()) |hl_entry| {
                    const hl: *Highlight = hl_entry.value_ptr;
                    _ = try window.printSegment(hl.segment, hl.print_options);
                }
            }
        }
        var count: usize = self.update_tasks.count();
        while (count > 0) : (count -= 1) {
            if (self.update_tasks.popOrNull()) |task| {
                if (task.done) {
                    self.allocator.destroy(task.wg);
                    self.allocator.destroy(task);
                    continue;
                }
                try self.update_tasks.insert(0, task);
            } else {
                break;
            }
        }
    }
};
