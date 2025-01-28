const std = @import("std");
const zts = @import("zts");
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
const ConcurrentStringHashMap = @import("../containers//concurrent_string_hash_map.zig").ConcurrentStringHashMap;

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

fn loadHighlightQueries(allocator: std.mem.Allocator, grammar: zts.LanguageGrammar) !Queries {
    const config_dir_path = try known_folders.getPath(allocator, known_folders.KnownFolder.roaming_configuration) orelse return error.NoDotConfigDirectory;
    defer allocator.free(config_dir_path);
    const full_path = try std.fmt.allocPrint(allocator, "{s}{s}{s}/highlights.scm", .{ config_dir_path, TREE_SITTER_QUERIES_PATH, @tagName(grammar) });
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
const Highlights = ConcurrentArrayList(Highlight);
const QueryHighlights = ConcurrentStringHashMap(*Highlights);
const LineQueryHighlights = std.ArrayList(QueryHighlights);

const QueryTask = struct {
    task: Pool.Task = .{ .callback = @This().callback },
    wg: *std.Thread.WaitGroup,
    parent: *TreeSitter,
    lines: *std.ArrayList(std.ArrayList(u8)),
    buffer_size: usize,
    highlights: *ThreadHighlights,
    root: zts.Node,

    fn callback(task: *Pool.Task) void {
        const self: *@This() = @alignCast(@fieldParentPtr("task", task));
        defer self.wg.finish();
        const idx_start = self.highlights.index;
        const idx_end = idx_start + self.highlights.count;
        for (idx_start..idx_end) |i| {
            const query_string = self.parent.queries.elems.keys()[i];
            var tags = self.parent.queries.elems.get(query_string);
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
            cursor.setByteRange(0, @intCast(self.buffer_size));
            cursor.setPointRange(
                .{ .row = 0, .column = 0 },
                .{ .row = @intCast(self.lines.items.len), .column = 0 },
            );
            var match: zts.QueryMatch = undefined;
            while (true) {
                if (!cursor.nextMatch(&match)) {
                    break;
                }
                const captures: [*]const zts.QueryCapture = @ptrCast(match.captures);
                for (0..match.capture_count) |j| {
                    const node = captures[j].node;
                    self.storeHighlight(query_string.items, &tags, node) catch |err| {
                        std.log.err(
                            "Failed to store highlight: {s} :: [Column: {d}] [Line: {d}] [Query: {s}] [Capture: {d}]",
                            .{
                                @errorName(err),
                                node.getStartPoint().column,
                                node.getStartPoint().row,
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

    fn storeHighlight(self: *@This(), query_string: []const u8, tags: *?Tags, node: zts.Node) !void {
        const start = node.getStartPoint();
        const end = node.getEndPoint();
        var style: vaxis.Style = .{};
        var tag: ?Tag = null;
        if (tags.* != null and tags.*.?.items.len > 0) {
            tag = tags.*.?.getLast();
            const theme_highlight = self.parent.config.theme.get(tag.?.items);
            if (theme_highlight) |hl| {
                style.fg = hl.colour;
                style.bold = hl.bold;
                style.italic = hl.italic;
                if (hl.underline) {
                    style.ul = hl.colour;
                }
            }
        }
        var query_highlights: *QueryHighlights = &self.parent.highlights.items[@intCast(start.row)];
        query_highlights.rwlock.lock();
        defer query_highlights.rwlock.unlock();
        var highlights = query_highlights.map.get(query_string);
        if (highlights == null) {
            std.log.err("Adding new highlights mapping", .{});
            highlights = try self.parent.allocator.create(Highlights);
            highlights.?.* = Highlights.init(self.parent.allocator);
            try query_highlights.map.put(query_string, highlights.?);
        }
        try highlights.?.append(.{
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
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?*zts.Tree,
    queries: Queries,
    per_thread_highlights: []ThreadHighlights,
    highlights: LineQueryHighlights,
    render_thread_pool: Pool,

    pub fn initFromFileExtension(allocator: std.mem.Allocator, config: Config, extension: []const u8) !?TreeSitter {
        const grammar: zts.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(allocator, config, try loadGrammar(grammar), grammar);
    }

    pub fn init(allocator: std.mem.Allocator, config: Config, language: *const zts.Language, grammar: zts.LanguageGrammar) !TreeSitter {
        const parser = try zts.Parser.init();
        try parser.setLanguage(language);
        var queries = try loadHighlightQueries(allocator, grammar);
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
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parser.deinit();
        self.queries.deinit();
        self.allocator.free(self.per_thread_highlights);
        self.render_thread_pool.deinit();
        for (0..self.highlights.items.len) |i| {
            self.highlights.items[i].deinit();
        }
        for (self.highlights.items) |*hls| {
            var iter = hls.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            hls.deinit();
        }
        self.highlights.deinit();
    }

    pub fn parseBuffer(self: *@This(), buffer: []const u8, lines: *std.ArrayList(std.ArrayList(u8))) !void {
        self.tree = try self.parser.parseString(self.tree, buffer);
        for (self.highlights.items) |*hls| {
            var iter = hls.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.*.deinit();
                self.allocator.destroy(entry.value_ptr.*);
            }
            hls.deinit();
        }
        self.highlights.deinit();
        self.highlights = LineQueryHighlights.init(self.allocator);
        for (0..lines.items.len) |_| {
            try self.highlights.append(QueryHighlights.init(self.allocator));
        }
        const root = self.tree.?.rootNodeWithOffset(0, .{
            .row = 0,
            .column = 0,
        });
        const tasks: []QueryTask = try self.allocator.alloc(QueryTask, self.per_thread_highlights.len);
        defer self.allocator.free(tasks);
        var wg = std.Thread.WaitGroup{};
        defer wg.wait();
        for (tasks, 0..) |*task, i| {
            wg.start();
            task.* = .{
                .wg = &wg,
                .parent = self,
                .lines = lines,
                .buffer_size = buffer.len,
                .highlights = &self.per_thread_highlights[i],
                .root = root,
            };
            Pool.schedule(&self.render_thread_pool, &task.task);
        }
    }

    pub fn drawBuffer(self: *@This(), window: vaxis.Window, window_lines_offset: Range) !void {
        // NOTE: If necessary at some stage this can be parallelised, but I doubt
        //       that it will need to be. I also feel like I'm going to look at this
        //       comment in future and say "Wow.. that was dumb".. but yeah.
        for (window_lines_offset.start..window_lines_offset.end) |i| {
            var query_highlights: QueryHighlights = self.highlights.items[i];
            var iter = query_highlights.iterator();
            while (iter.next()) |entry| {
                var highlights: *Highlights = entry.value_ptr.*;
                highlights.rwlock.lockShared();
                for (highlights.array_list.items) |hl| {
                    _ = try window.printSegment(hl.segment, hl.print_options);
                }
                highlights.rwlock.unlockShared();
            }
        }
    }
};
