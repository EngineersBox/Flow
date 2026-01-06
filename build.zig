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
    const notcurses = try addNotcursesCLibrary(
        b,
        target,
        optimize,
        mod,
    );
    b.installArtifact(notcurses);
    mod.linkLibrary(notcurses);
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

// Big help from:
// - https://github.com/dundalek/notcurses-zig-example
// - https://github.com/dundalek/notcurses-zig-example/pull/6
fn addNotcursesCLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_module: *std.Build.Module,
) !*std.Build.Step.Compile {
    const notcurses_source_path = "external/notcurses";
    root_module.addIncludePath(b.path(notcurses_source_path ++ "/include"));
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = .off,
    });
    mod.linkSystemLibrary("deflate", .{.preferred_link_mode = .static});
    mod.linkSystemLibrary("ncurses", .{.preferred_link_mode = .static});
    mod.linkSystemLibrary("readline", .{.preferred_link_mode = .static});
    mod.linkSystemLibrary("unistring", .{.preferred_link_mode = .static});
    mod.linkSystemLibrary("z", .{.preferred_link_mode = .static});
    mod.addIncludePath(b.path(notcurses_source_path ++ "/include"));
    mod.addIncludePath(b.path(notcurses_source_path ++ "/build/include"));
    mod.addIncludePath(b.path(notcurses_source_path ++ "/src"));
    var files: std.ArrayList([]const u8) = try .initCapacity(b.allocator, 0);
    defer {
        for (files.items) |file| {
            b.allocator.free(file);
        }
        files.deinit(b.allocator);
    }
    try collectCSources(b, notcurses_source_path ++ "/src/lib/", &files);
    try collectCSources(b, notcurses_source_path ++ "/src/compat/", &files);
    mod.addCSourceFiles(.{
        .files = files.items,
        .flags = &[_][]const u8{
            "-std=gnu11",
            "-D_GNU_SOURCE",
            "-DUSE_MULTIMEDIA=none",
        }
    });
    const notcurses: *std.Build.Step.Compile = b.addLibrary(.{
        .name = "notcurses",
        .linkage = .static,
        .root_module = mod,
    });
    return notcurses;
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
