const std = @import("std");
const zts = @import("zts");
const vaxis = @import("vaxis");
const colours = @import("colours.zig");
const logToFile = @import("log.zig").logToFile;

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

pub const TreeSitter = struct {
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?*zts.Tree,
    line: usize,

    pub fn initFromFileExtension(extension: []const u8) !?TreeSitter {
        const grammar: zts.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(try loadGrammar(grammar));
    }

    pub fn init(language: *const zts.Language) !TreeSitter {
        const parser = try zts.Parser.init();
        try parser.setLanguage(language);
        return .{
            .language = language,
            .parser = parser,
            .tree = null,
            .line = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.parser.deinit();
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

    pub fn drawBuffer(self: *@This(), lines: *std.ArrayList(std.ArrayList(u8)), _: vaxis.Window, window_start_offset: usize, window_width: usize, window_height: usize) !void {
        const root = self.tree.?.rootNodeWithOffset(@intCast(window_start_offset), .{
            .row = @intCast(window_width),
            .column = @intCast(window_height),
        });
        var iter = TreeIterator.init(root);
        var line: u32 = 0;
        var col: u32 = 0;
        while (iter.next()) |node| {
            const start = node.getStartPoint();
            if (line != start.row) {
                while (line < start.row) : (line += 1) {
                    try logToFile("\n", .{});
                }
                col = 0;
            } else {
                // NOTE: After converting to render code, this can be
                //       just an allocated array with a @memset
                while (col < start.column) : (col += 1) {
                    try logToFile(" ", .{});
                }
            }
            const end = node.getEndPoint();
            if (node.isNamed()) {
                const string = lines.items[line];
                try logToFile("{s}", .{string.items[start.column..end.column]});
            } else {
                try logToFile("{s}", .{node.getType()});
            }
            col += end.column;
        }
        return error.DebugError;
    }
};
