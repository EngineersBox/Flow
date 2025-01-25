const std = @import("std");
const zts = @import("zts");
const vaxis = @import("vaxis");
const colours = @import("colours.zig");
const Query = @import("query.zig").Query;
const Queries = @import("query.zig").Queries;
const Pool = @import("zap");
const Config = @import("config.zig").Config;
const known_folders = @import("known-folders");
const json = @import("json");
const fb = @import("buffer.zig");
const Range = fb.Range;

pub const TreeIterator = struct {
    cursor: zts.TreeCursor,
    vistied_children: bool,
    yielded: bool,

    pub fn init(node: zts.Node) TreeIterator {
        return .{
            .cursor = zts.TreeCursor.init(node),
            .vistied_children = false,
            .yielded = false,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.cursor.deinit();
    }

    pub fn next(self: *@This()) ?zts.Node {
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
                return self.cursor.currentNode();
            } else if (self.cursor.gotoNextSibling()) {
                self.vistied_children = false;
            } else if (!self.cursor.gotoParent()) {
                break;
            }
        }
        return null;
    }
};

const file_extension_languages = std.StaticStringMap(zts.LanguageGrammar).initComptime(.{
    .{ "sh", zts.LanguageGrammar.bash },
    .{ "c", zts.LanguageGrammar.c },
    .{ "h", zts.LanguageGrammar.c },
    .{ "css", zts.LanguageGrammar.css },
    .{ "cpp", zts.LanguageGrammar.cpp },
    .{ "c++", zts.LanguageGrammar.cpp },
    .{ "cc", zts.LanguageGrammar.cpp },
    .{ "hpp", zts.LanguageGrammar.cpp },
    .{ "h++", zts.LanguageGrammar.cpp },
    .{ "cs", zts.LanguageGrammar.c_sharp },
    .{ "ex", zts.LanguageGrammar.elixir },
    .{ "exs", zts.LanguageGrammar.elixir },
    .{ "elm", zts.LanguageGrammar.elm },
    .{ "erl", zts.LanguageGrammar.erlang },
    .{ "hrl", zts.LanguageGrammar.erlang },
    .{ "fs", zts.LanguageGrammar.fsharp },
    .{ "fsi", zts.LanguageGrammar.fsharp },
    .{ "fsx", zts.LanguageGrammar.fsharp },
    .{ "fsscript", zts.LanguageGrammar.fsharp },
    .{ "go", zts.LanguageGrammar.go },
    .{ "hs", zts.LanguageGrammar.haskell },
    .{ "lhs", zts.LanguageGrammar.haskell },
    .{ "java", zts.LanguageGrammar.java },
    .{ "js", zts.LanguageGrammar.javascript },
    .{ "cjs", zts.LanguageGrammar.javascript },
    .{ "mjs", zts.LanguageGrammar.javascript },
    .{ "jsx", zts.LanguageGrammar.javascript },
    .{ "json", zts.LanguageGrammar.json },
    .{ "jl", zts.LanguageGrammar.julia },
    .{ "kt", zts.LanguageGrammar.kotlin },
    .{ "kts", zts.LanguageGrammar.kotlin },
    .{ "kexe", zts.LanguageGrammar.kotlin },
    .{ "klib", zts.LanguageGrammar.kotlin },
    .{ "lua", zts.LanguageGrammar.lua },
    .{ "md", zts.LanguageGrammar.markdown },
    .{ "nim", zts.LanguageGrammar.nim },
    .{ "nims", zts.LanguageGrammar.nim },
    .{ "nimble", zts.LanguageGrammar.nim },
    .{ "ml", zts.LanguageGrammar.ocaml },
    .{ "mli", zts.LanguageGrammar.ocaml },
    .{ "perl", zts.LanguageGrammar.perl },
    .{ "plx", zts.LanguageGrammar.perl },
    .{ "pls", zts.LanguageGrammar.perl },
    .{ "pl", zts.LanguageGrammar.perl },
    .{ "pm", zts.LanguageGrammar.perl },
    .{ "xs", zts.LanguageGrammar.perl },
    .{ "t", zts.LanguageGrammar.perl },
    .{ "pod", zts.LanguageGrammar.perl },
    .{ "cgi", zts.LanguageGrammar.perl },
    .{ "psgi", zts.LanguageGrammar.perl },
    .{ "php", zts.LanguageGrammar.php },
    .{ "py", zts.LanguageGrammar.python },
    .{ "pyc", zts.LanguageGrammar.python },
    .{ "rb", zts.LanguageGrammar.ruby },
    .{ "rs", zts.LanguageGrammar.rust },
    .{ "scala", zts.LanguageGrammar.scala },
    .{ "sc", zts.LanguageGrammar.scala },
    .{ "toml", zts.LanguageGrammar.toml },
    .{ "ts", zts.LanguageGrammar.typescript },
    .{ "tsx", zts.LanguageGrammar.typescript },
    .{ "zig", zts.LanguageGrammar.zig },
    .{ "zon", zts.LanguageGrammar.zig },
});

fn loadGrammar(grammar: zts.LanguageGrammar) !*const zts.Language {
    inline for (@typeInfo(zts.LanguageGrammar).Enum.fields) |field| {
        // NOTE: With `inline for` the function gets generated as
        //       a series of `if` statements relying on the optimizer
        //       to convert it to a switch.
        if (field.value == @intFromEnum(grammar)) {
            return try zts.loadLanguage(@as(zts.LanguageGrammar, @enumFromInt(field.value)));
        }
    }
    // NOTE: When using `inline for` the compiler doesn't know that every
    //       possible case has been handled requiring an explicit `unreachable`.
    unreachable;
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
const Highlights = std.ArrayList(Highlight);
const QueryHighlightsContext = struct {
    pub fn hash(self: @This(), s: Query) u32 {
        _ = self;
        return std.array_hash_map.hashString(s.items);
    }
    pub fn eql(self: @This(), a: Query, b: Query, b_index: usize) bool {
        _ = self;
        _ = b_index;
        return std.array_hash_map.eqlString(a.items, b.items);
    }
};
const QueryHighlights = struct {
    allocator: std.mem.Allocator,
    rwlock: std.Thread.RwLock,
    map: std.ArrayHashMap(Query, Highlights, QueryHighlightsContext, true),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .rwlock = std.Thread.RwLock{},
            .map = std.ArrayHashMap(Query, Highlights, QueryHighlightsContext, true).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.map.deinit();
    }

    pub fn put(self: *@This(), query: Query, highlights: Highlights) !void {
        self.rwlock.lock();
        defer self.rwlock.unlock();
        try self.map.put(query, highlights);
    }

    pub fn get(self: *@This(), query: Query) ?Highlights {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();
        return self.map.get(query);
    }
};

const QueryTask = struct {
    task: Pool.Task = .{ .callback = @This().callback },
    wg: *std.Thread.WaitGroup,
    parent: *TreeSitter,
    lines: *std.ArrayList(std.ArrayList(u8)),
    window_offset: Range,
    window_lines_offset: Range,
    window_offset_width: usize,
    window_offset_height: usize,
    window_height: usize,
    highlights: *ThreadHighlights,
    root: zts.Node,

    fn callback(task: *Pool.Task) void {
        const self: *@This() = @alignCast(@fieldParentPtr("task", task));
        defer self.wg.finish();
        const idx_start = self.highlights.index;
        const idx_end = idx_start + self.highlights.count;
        for (idx_start..idx_end) |i| {
            const query_string = self.parent.queries.elems.keys()[i];
            const tags = self.parent.queries.elems.get(query_string);
            var query = zts.Query.init(self.parent.language, query_string.items) catch {
                std.log.err("Failed to init query", .{});
                continue;
            };
            defer query.deinit();
            _ = query.captureCount();
            _ = query.stringCount();
            _ = query.patternCount();
            _ = query.startByteForPattern(0);
            _ = query.endByteForPattern(@intCast(query_string.items.len));
            var cursor = zts.QueryCursor.init() catch {
                std.log.err("Failed to init query cursor", .{});
                continue;
            };
            defer cursor.deinit();
            cursor.exec(query, self.root);
            cursor.setByteRange(@intCast(self.window_offset.start), @intCast(self.window_offset.end));
            cursor.setPointRange(.{ .row = 0, .column = 0 }, .{ .row = @intCast(self.window_height), .column = 0 });
            var match: zts.QueryMatch = undefined;
            var highlights = Highlights.init(self.parent.allocator);
            while (true) {
                if (!cursor.nextMatch(&match)) {
                    break;
                }
                const captures: [*]const zts.QueryCapture = @ptrCast(match.captures);
                for (0..match.capture_count) |j| {
                    const node = captures[j].node;
                    const start = node.getStartPoint();
                    const end = node.getEndPoint();
                    var style: vaxis.Style = .{};
                    if (tags != null and tags.?.items.len > 0) {
                        const tag = tags.?.getLast();
                        const theme_highlight = self.parent.config.theme.get(tag.items);
                        if (theme_highlight) |hl| {
                            style.fg = hl.colour;
                            style.bold = hl.bold;
                            style.italic = hl.italic;
                            if (hl.underline) {
                                style.ul = hl.colour;
                            }
                        }
                    }
                    highlights.append(Highlight{
                        .child_options = .{
                            .x_off = start.column - self.window_lines_offset.start,
                            .y_off = start.row,
                            .width = .{ .limit = end.column - start.column },
                            .height = .{ .limit = @max(1, end.row - start.row) },
                        },
                        .segment = .{
                            .text = self.lines.items[start.row].items[start.column..end.column],
                            .style = style,
                        },
                        .print_options = .{},
                    }) catch {
                        std.log.err("Failed to append highlight capture {d} for query {s}", .{ j, query_string.items });
                    };
                }
                cursor.removeMatch(0);
            }
            self.parent.highlights.put(query_string, highlights) catch {
                std.log.err("Failed to store {d} highlights for query: {s}", .{ highlights.items.len, query_string.items });
            };
        }
    }
};

pub const TreeSitter = struct {
    allocator: std.mem.Allocator,
    config: Config,
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?*zts.Tree,
    queries: Queries,
    per_thread_highlights: []ThreadHighlights,
    highlights: QueryHighlights,
    render_thread_pool: Pool,

    pub fn initFromFileExtension(allocator: std.mem.Allocator, config: Config, extension: []const u8) !?TreeSitter {
        const grammar: zts.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(allocator, config, try loadGrammar(grammar));
    }

    pub fn init(allocator: std.mem.Allocator, config: Config, language: *const zts.Language) !TreeSitter {
        const parser = try zts.Parser.init();
        try parser.setLanguage(language);
        const hl_file = try std.fs.openFileAbsolute("/Users/jackkilrain/.config/flow/queries/zig/highlights.scm", .{ .mode = .read_only });
        defer hl_file.close();
        const hl_queries = try hl_file.readToEndAlloc(allocator, 1024 * 1024 * 1024);
        defer allocator.free(hl_queries);
        var queries = Queries.init(allocator, hl_queries);
        try queries.parseQueries();
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
            .highlights = QueryHighlights.init(allocator),
            .render_thread_pool = Pool.init(@max(1, std.Thread.getCpuCount() catch 1)),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parser.deinit();
        self.queries.deinit();
        self.allocator.free(self.per_thread_highlights);
        self.render_thread_pool.deinit();
        self.highlights.deinit();
    }

    pub fn parseBuffer(self: *@This(), buffer: []const u8, lines: *std.ArrayList(std.ArrayList(u8)), window_offset: Range, window_lines_offset: Range, window_offset_width: usize, window_offset_height: usize, window_height: usize) !void {
        self.tree = try self.parser.parseString(self.tree, buffer);
        self.highlights.deinit();
        self.highlights = QueryHighlights.init(self.allocator);
        const root = self.tree.?.rootNodeWithOffset(@intCast(window_offset.start), .{
            .row = @intCast(window_offset_width),
            .column = @intCast(window_offset_height),
        });
        const tasks: []QueryTask = try self.allocator.alloc(QueryTask, self.per_thread_highlights.len);
        defer self.allocator.free(tasks);
        var wg = std.Thread.WaitGroup{};
        defer wg.wait();
        for (tasks, 0..) |*task, i| {
            wg.start();
            task.* = .{ .wg = &wg, .parent = self, .lines = lines, .window_offset = window_offset, .window_lines_offset = window_lines_offset, .window_offset_width = window_offset_width, .window_offset_height = window_offset_height, .window_height = window_height, .highlights = &self.per_thread_highlights[i], .root = root };
            Pool.schedule(&self.render_thread_pool, &task.task);
        }
    }

    pub fn drawBuffer(self: *@This(), window: vaxis.Window) !void {
        // NOTE: If necessary at some stage this can be parallelised, but I doubt
        //       that it will need to be. I also feel like I'm going to look at this
        //       comment in future and say "Wow.. that was dumb".. but yeah.
        const keys = self.queries.elems.keys();
        // FIXME: Change QueryHighlights to store a list of highlights for
        //        a row index so that moving windows can just index without
        //        needing to filter through all the highlights every time
        //        a render call happens.
        for (keys) |key| {
            const query_highlights = self.highlights.get(key) orelse continue;
            for (query_highlights.items) |highlight| {
                // TODO: Avoid creating a child by setting row/column offsets
                //       in print_options to print to screen correctly.
                const child = window.child(highlight.child_options);
                _ = try child.printSegment(highlight.segment, highlight.print_options);
            }
        }
    }
};
