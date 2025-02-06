const ts = @import("tree-sitter");

pub const grammars = @cImport({
    @cInclude("zig.h");
});

pub const LanguageGrammar = enum {
    // bash,
    // c,
    // css,
    // cpp,
    // c_sharp,
    // elixir,
    // elm,
    // erlang,
    // fsharp,
    // go,
    // haskell,
    // java,
    // javascript,
    // json,
    // julia,
    // kotlin,
    // lua,
    // markdown,
    // nim,
    // ocaml,
    // perl,
    // php,
    // python,
    // ruby,
    // rust,
    // scala,
    // toml,
    // typescript,
    zig,
};

pub inline fn loadLanguage(comptime lg: LanguageGrammar) !*const ts.Language {
    const name = @tagName(lg);
    const c_func = @field(grammars, "tree_sitter_" ++ name);
    return if (c_func()) |lang| @ptrCast(lang) else error.InvalidLanguage;
}
