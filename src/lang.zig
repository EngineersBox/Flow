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

    pub fn initFromFileExtension(extension: []const u8) !?TreeSitter {
        const grammar: zts.LanguageGrammar = file_extension_languages.get(extension) orelse {
            return null;
        };
        // const language = switch (grammar) {
        // zts.LanguageGrammar.bash => try zts.loadLanguage(zts.LanguageGrammar.bash),
        // zts.LanguageGrammar.c => try zts.loadLanguage(zts.LanguageGrammar.c),
        // zts.LanguageGrammar.css => try zts.loadLanguage(zts.LanguageGrammar.css),
        // zts.LanguageGrammar.cpp => try zts.loadLanguage(zts.LanguageGrammar.cpp),
        // zts.LanguageGrammar.c_sharp => try zts.loadLanguage(zts.LanguageGrammar.c_sharp),
        // zts.LanguageGrammar.elixir => try zts.loadLanguage(zts.LanguageGrammar.elixir),
        // zts.LanguageGrammar.elm => try zts.loadLanguage(zts.LanguageGrammar.elm),
        // zts.LanguageGrammar.erlang => try zts.loadLanguage(zts.LanguageGrammar.erlang),
        // zts.LanguageGrammar.fsharp => try zts.loadLanguage(zts.LanguageGrammar.fsharp),
        // zts.LanguageGrammar.go => try zts.loadLanguage(zts.LanguageGrammar.go),
        // zts.LanguageGrammar.haskell => try zts.loadLanguage(zts.LanguageGrammar.haskell),
        // zts.LanguageGrammar.java => try zts.loadLanguage(zts.LanguageGrammar.java),
        // zts.LanguageGrammar.javascript => try zts.loadLanguage(zts.LanguageGrammar.javascript),
        // zts.LanguageGrammar.json => try zts.loadLanguage(zts.LanguageGrammar.json),
        // zts.LanguageGrammar.julia => try zts.loadLanguage(zts.LanguageGrammar.julia),
        // zts.LanguageGrammar.kotlin => try zts.loadLanguage(zts.LanguageGrammar.kotlin),
        // zts.LanguageGrammar.lua => try zts.loadLanguage(zts.LanguageGrammar.lua),
        // zts.LanguageGrammar.markdown => try zts.loadLanguage(zts.LanguageGrammar.markdown),
        // zts.LanguageGrammar.nim => try zts.loadLanguage(zts.LanguageGrammar.nim),
        // zts.LanguageGrammar.ocaml => try zts.loadLanguage(zts.LanguageGrammar.ocaml),
        // zts.LanguageGrammar.perl => try zts.loadLanguage(zts.LanguageGrammar.perl),
        // zts.LanguageGrammar.php => try zts.loadLanguage(zts.LanguageGrammar.php),
        // zts.LanguageGrammar.python => try zts.loadLanguage(zts.LanguageGrammar.python),
        // zts.LanguageGrammar.ruby => try zts.loadLanguage(zts.LanguageGrammar.ruby),
        // zts.LanguageGrammar.rust => try zts.loadLanguage(zts.LanguageGrammar.rust),
        // zts.LanguageGrammar.scala => try zts.loadLanguage(zts.LanguageGrammar.scala),
        // zts.LanguageGrammar.toml => try zts.loadLanguage(zts.LanguageGrammar.toml),
        // zts.LanguageGrammar.typescript => try zts.loadLanguage(zts.LanguageGrammar.typescript),
        // zts.LanguageGrammar.zig => try zts.loadLanguage(zts.LanguageGrammar.zig),
        // };
        return try TreeSitter.init(try loadGrammar(grammar));
    }

    pub fn init(language: *const zts.Language) !TreeSitter {
        const parser = try zts.Parser.init();
        try parser.setLanguage(language);
        return .{
            .language = language,
            .parser = parser,
            .tree = null,
        };
    }

    pub fn deinit(self: *TreeSitter) void {
        self.parser.deinit();
    }

    pub fn parseString(self: *TreeSitter, string: []const u8) !void {
        self.tree = try self.parser.parseString(self.tree, string);
    }
};
