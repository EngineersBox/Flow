const std = @import("std");
const zts = @import("zts");

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

pub const TreeSitter = struct {
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?*const zts.Tree,

    pub fn initFromFileExtension(extension: []const u8) !?TreeSitter {
        const language = file_extension_languages.get(extension) orelse {
            return null;
        };
        return try TreeSitter.init(language);
    }

    pub fn init(language: zts.LanguageGrammar) !TreeSitter {
        const lang = try zts.loadLanguage(language);
        const parser = try zts.Parser.init();
        try parser.setLanguage(language);
        return .{
            .language = lang,
            .parser = parser,
            .tree = null,
        };
    }

    pub fn deinit(self: *TreeSitter) void {
        self.parser.deinit();
    }

    pub fn parseBuffer(self: *TreeSitter, buffer: []const u8) !void {
        self.tree = try self.parser.parse(self.tree, buffer);
    }
};
