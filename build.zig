const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;
const allocator = std.heap.page_allocator;

const Grammar = struct {
    name: []const u8,
    root: []const u8 = "src",
    scanner: bool = true,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "flow",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    //Grammars options
    for (grammars) |g| {
        const grammar_build = try buildLanguageGrammar(b, target, optimize, g);
        b.installArtifact(grammar_build);
        exe.linkLibrary(grammar_build);
    }

    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const piecetable = b.dependency("piecetable", .{
        .target = target,
        .optimize = optimize,
    });
    const zap = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
    const known_folders = b.dependency("known-folders", .{
        .target = target,
        .optimize = optimize,
    });
    const toml = b.dependency("zig-toml", .{
        .target = target,
        .optimize = optimize,
    });
    const tree_sitter = b.dependency("tree-sitter", .{
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    exe.root_module.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe.root_module.addImport("piecetable", piecetable.module("piecetable"));
    exe.root_module.addImport("zap", zap.module("zap"));
    exe.root_module.addImport("known-folders", known_folders.module("known-folders"));
    exe.root_module.addImport("zig-toml", toml.module("zig-toml"));
    exe.root_module.addImport("tree-sitter", tree_sitter.module("tree-sitter"));

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn buildLanguageGrammar(
    b: *Build,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    g: Grammar,
) !*Step.Compile {
    const dep = b.dependency(g.name, .{
        .target = target,
        .optimize = optimize,
    });

    const lib = dep.builder.addStaticLibrary(.{
        .name = g.name,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const default_files = &.{ "parser.c", "scanner.c" };
    lib.addCSourceFiles(.{
        .root = dep.path(g.root),
        .files = if (g.scanner) default_files else &.{"parser.c"},
        .flags = &.{"-std=c11"},
    });
    lib.addIncludePath(dep.path(g.root));

    const path = try generateHeaderFile(b, g, dep);
    lib.installHeader(dep.path(path), path);

    return lib;
}

fn generateHeaderFile(b: *Build, g: Grammar, dep: *std.Build.Dependency) ![]const u8 {
    // TODO: Detect if the dependency already has a header definition provided
    const path = dep.path("").getPath(b);
    const dir = try std.fs.openDirAbsolute(path, .{});

    const file_name = try std.fmt.allocPrint(allocator, "{s}.h", .{g.name});

    var buf: [32]u8 = undefined;
    const upper_name = std.ascii.upperString(&buf, file_name);

    const f = try dir.createFile(file_name, .{});
    defer f.close();

    const writer = f.writer();
    try writer.print(
        \\#ifndef TREE_SITTER_{s}_H_
        \\#define TREE_SITTER_{s}_H_
        \\typedef struct TSLanguage TSLanguage;
        \\#ifdef __cplusplus
        \\extern "C"
        \\{{
        \\#endif
        \\const TSLanguage *tree_sitter_{s}(void);
        \\#ifdef __cplusplus
        \\}}
        \\#endif
        \\#endif
    ,
        .{ upper_name, upper_name, g.name },
    );
    return file_name;
}

// TODO: Add language dependencies for other languages
const grammars = [_]Grammar{
    // .{ .name = "bash" },
    // .{ .name = "c", .scanner = false },
    // .{ .name = "css" },
    // .{ .name = "cpp" },
    // .{ .name = "c_sharp" },
    // .{ .name = "elixir" },
    // .{ .name = "elm" },
    // .{ .name = "erlang", .scanner = false },
    // .{ .name = "fsharp", .root = "fsharp/src" },
    // .{ .name = "go", .scanner = false },
    // .{ .name = "haskell" },
    // .{ .name = "java", .scanner = false },
    // .{ .name = "javascript" },
    // .{ .name = "json", .scanner = false },
    // .{ .name = "julia" },
    // .{ .name = "kotlin" },
    // .{ .name = "lua" },
    // .{ .name = "markdown", .root = "tree-sitter-markdown/src" },
    // .{ .name = "nim" },
    // .{ .name = "ocaml", .root = "grammars/ocaml/src" },
    // .{ .name = "perl" },
    // .{ .name = "php", .root = "php/src" },
    // .{ .name = "python" },
    // .{ .name = "ruby" },
    // .{ .name = "rust" },
    // .{ .name = "scala" },
    // .{ .name = "toml" },
    // .{ .name = "typescript", .root = "typescript/src" },
    .{ .name = "zig", .scanner = false },
};
