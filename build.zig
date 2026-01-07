const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("flow", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const notcurses_lib_path = "external/notcurses";
    try addCLibrary(
        b,
        b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off, // Causes memory issues
        }),
        mod,
        "notcurses",
        &[_][]const u8{notcurses_lib_path ++ "/include"},
        &[_][]const u8{"deflate", "ncurses", "unistring", "readline", "z"},
        &[_][]const u8{
            notcurses_lib_path ++ "/include",
            notcurses_lib_path ++ "/build/include",
            notcurses_lib_path ++ "/src"
        },
        &[_][]const u8{
            notcurses_lib_path ++ "/src/lib/",
            notcurses_lib_path ++ "/src/compat/"
        },
        &[_][]const u8{
            "-std=gnu11",
            "-D_GNU_SOURCE",
            "-DUSE_MULTIMEDIA=none",
        }
    );
    const piecechain_lib_path = "external/PieceChain";
    try addCLibrary(
        b,
        b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off, // Causes memory issues
        }),
        mod,
        "piecechain",
        &[_][]const u8{piecechain_lib_path ++ "/include"},
        &[_][]const u8{},
        &[_][]const u8{
            piecechain_lib_path ++ "/include",
            piecechain_lib_path ++ "/src"
        },
        &[_][]const u8{piecechain_lib_path ++ "/src/"},
        &[_][]const u8{
            "-std=gnu11"
        },
    );
    const tree_sitter = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("tree-sitter", tree_sitter.module("tree_sitter"));
    const known_folders = b.dependency("known_folders", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("known-folders", known_folders.module("known-folders"));
    const exe = b.addExecutable(.{
        .name = "flow",
        .root_module = mod,
    });
    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    // const mod_tests = b.addTest(.{
    //     .root_module = mod,
    // });
    // const run_mod_tests = b.addRunArtifact(mod_tests);
    // const exe_tests = b.addTest(.{
    //     .root_module = exe.root_module,
    // });
    // const run_exe_tests = b.addRunArtifact(exe_tests);
    // const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    // test_step.dependOn(&run_exe_tests.step);
}

fn addCLibrary(
    b: *std.Build,
    mod: *std.Build.Module,
    root_module: *std.Build.Module,
    comptime name: []const u8,
    comptime root_module_include_paths: []const []const u8,
    comptime system_libraries: []const []const u8,
    comptime include_paths: []const []const u8,
    comptime source_paths: []const []const u8,
    comptime compile_flags: []const []const u8,
) !void {
    for (root_module_include_paths) |p| {
        root_module.addIncludePath(b.path(p));
    }
    for (system_libraries) |sys_lib| {
        mod.linkSystemLibrary(sys_lib, .{ .preferred_link_mode = .static });
    }
    for (include_paths) |inc_path| {
        mod.addIncludePath(b.path(inc_path));
    }
    var files: std.ArrayList([]const u8) = try .initCapacity(b.allocator, 0);
    defer {
        for (files.items) |file| {
            b.allocator.free(file);
        }
        files.deinit(b.allocator);
    }
    for (source_paths) |src_path| {
        try collectCSources(b, src_path, &files);
    }
    mod.addCSourceFiles(.{
        .files = files.items,
        .flags = compile_flags,
    });
    const library: *std.Build.Step.Compile = b.addLibrary(.{
        .name = name,
        .linkage = .static,
        .root_module = mod,
    });
    b.installArtifact(library);
    root_module.linkLibrary(library);
}

fn collectCSources(b: *std.Build, path: []const u8, files: *std.ArrayList([]const u8)) !void {
    var dir: std.fs.Dir = try std.fs.cwd().openDir(
        path,
        .{ .iterate = true }
    );
    var walker: std.fs.Dir.Walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        const ext: []const u8 = std.fs.path.extension(entry.basename);
        if (std.mem.eql(u8, ext, ".c")) {
            try files.append(
                b.allocator,
                try std.mem.concat(b.allocator, u8, &[_][]const u8{
                    path,
                    entry.path
                }),
            );
        }
    }
}
