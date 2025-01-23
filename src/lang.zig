const std = @import("std");
const zts = @import("zts");
const vaxis = @import("vaxis");
const colours = @import("colours.zig");
const logToFile = @import("log.zig").logToFile;
const Queries = @import("query.zig");
const Pool = @import("zap");
const config = @import("config.zig");
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

pub const TreeSitter = struct {
    allocator: std.mem.Allocator,
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?*zts.Tree,
    queries: Queries,
    line: usize,
    per_thread_highlights: []ThreadHighlights,
    render_thread_pool: Pool,

    pub fn initFromFileExtension(allocator: std.mem.Allocator, extension: []const u8) !?TreeSitter {
        const grammar: zts.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(allocator, try loadGrammar(grammar));
    }

    pub fn init(allocator: std.mem.Allocator, language: *const zts.Language) !TreeSitter {
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
            .language = language,
            .parser = parser,
            .tree = null,
            .queries = queries,
            .line = 0,
            .per_thread_highlights = per_thread_highlights,
            .render_thread_pool = Pool.init(@max(1, std.Thread.getCpuCount() catch 1)),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parser.deinit();
        self.queries.deinit();
    }

    pub fn parseBuffer(self: *@This(), buffer: []const u8) !void {
        self.tree = try self.parser.parseString(self.tree, buffer);
    }

    inline fn lineWidth(line: []const u8, window_width: usize) usize {
        if (line.len > window_width) {
            return window_width;
        } else if (line.len > 1 and std.mem.eql(u8, line[line.len - 1 ..], "\n")) {
            return line.len - 1;
        }
        return line.len;
    }

    // TODO: Move this elsewhere, it belongs somewhere that centralises
    //       rendering operations together.
    fn drawLine(self: *@This(), line: []const u8, y_offset: usize, window: vaxis.Window) !void {
        const new_tree = try self.parser.parseString(self.tree, line);
        if (self.tree) |old_tree| {
            old_tree.deinit();
        }
        self.tree = new_tree;
        const root = self.tree.?.rootNode();
        try logToFile("{s}\n", .{root.toString()});
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
    }

    // fn drawHighlights(self: *@This()) void {
    //     const Work = struct {
    //         task: Pool.Task = .{ .callback = @This().callback },
    //         wg: *std.Thread.WaitGroup,
    //
    //         fn callback(task: *Pool.Task) void {
    //             const task_self: *@This() = @alignCast(@fieldParentPtr("task", task));
    //             task_self.wg.finish();
    //         }
    //     };
    // }

    pub fn drawBuffer(self: *@This(), lines: *std.ArrayList(std.ArrayList(u8)), window: vaxis.Window, window_offset: Range, window_lines_offset: Range, window_offset_width: usize, window_offset_height: usize, window_height: usize) !void {
        const root = self.tree.?.rootNodeWithOffset(@intCast(window_offset.start), .{
            .row = @intCast(window_offset_width),
            .column = @intCast(window_offset_height),
        });
        // var iter = TreeIterator.init(root);

        var queries_iter = self.queries.elems.iterator();
        while (queries_iter.next()) |entry| {
            var query = try zts.Query.init(self.language, entry.key_ptr.*.items);
            _ = query.captureCount();
            _ = query.stringCount();
            _ = query.patternCount();
            _ = query.startByteForPattern(0);
            _ = query.endByteForPattern(50);
            var cursor = try zts.QueryCursor.init();
            cursor.exec(query, root);
            cursor.setByteRange(@intCast(window_offset.start), @intCast(window_offset.end));
            cursor.setPointRange(.{ .row = 0, .column = 0 }, .{ .row = @intCast(window_height), .column = 0 });
            var match: zts.QueryMatch = undefined;
            while (true) {
                if (!cursor.nextMatch(&match)) {
                    break;
                }
                const captures: [*]const zts.QueryCapture = @ptrCast(match.captures);
                for (0..match.capture_count) |i| {
                    const node = captures[i].node;
                    const start = node.getStartPoint();
                    const end = node.getEndPoint();
                    std.log.err("MATCH {d}: {s} :: ({d},{d})", .{ i, lines.items[start.row].items[start.column..end.column], start.column, start.row });
                    const segment = window.child(.{
                        .x_off = start.column - window_lines_offset.start,
                        .y_off = start.row,
                        .width = .{ .limit = end.column - start.column },
                        .height = .{ .limit = @max(1, end.row - start.row) },
                    });
                    // FIXME: This doesn't render for some reason
                    _ = try segment.printSegment(.{
                        .text = lines.items[start.row].items[start.column..end.column],
                        .style = .{
                            .bg = colours.BLACK,
                            .fg = colours.WHITE,
                            .reverse = false,
                        },
                    }, .{});
                }
                cursor.removeMatch(0);
            }
            query.deinit();
            cursor.deinit();
        }

        // var line: u32 = 0;
        // var col: u32 = 0;
        // std.log.err("Field count: {d}", .{self.language.getFieldCount()});
        // for (1..self.language.getFieldCount()) |i| {
        //     std.log.err("Field {d}: {s}", .{ i, self.language.getFieldNameForId(@intCast(i)) });
        // }
        // while (iter.next()) |node| {
        //     std.log.err("{s}", .{node.toString()});
        //     if (node.getChildCount() > 0) {
        //         std.log.err("{s}", .{node.toString()});
        //         // Only render leaf nodes that correspond to actual buffer symbols
        //         continue;
        //     }
        //     const start = node.getStartPoint();
        //     if (start.row > window_height) {
        //         // Reached the limit on lines
        //         break;
        //     }
        //     if (line != start.row) {
        //         while (line < start.row) : (line += 1) {
        //             try logToFile("\n", .{});
        //         }
        //         col = 0;
        //     }
        //     // NOTE: After converting to render code, this can be
        //     //       just an allocated array with a @memset
        //     while (col < start.column) : (col += 1) {
        //         try logToFile(" ", .{});
        //     }
        //     const end = node.getEndPoint();
        //     if (!node.isNamed() and self.language.getSymbolType(node.getSymbol()) == zts.SymbolType.anonymous) {
        //         // Literal character as a node
        //         try logToFile("{s}", .{node.getType()});
        //     } else {
        //         // Segment of buffer content
        //         const string = lines.items[line];
        //         try logToFile("{s}", .{string.items[start.column..end.column]});
        //     }
        //     col = end.column;
        // }
        // iter.deinit();
        // return error.DebugError;
    }
};
