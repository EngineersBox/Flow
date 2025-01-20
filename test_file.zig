const std = @import("std");
const vaxis = @import("vaxis");
const Flow = @import("flow.zig").Flow;

/// Keep our main function small. Typically handling arg parsing and initialization only
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        std.process.argsFree(allocator, args);
        std.log.err("Usage: flow <file path>\n", .{});
        return;
    }
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const file_path = try std.fs.path.resolve(allocator, &.{ cwd_path, args[1] });
    defer allocator.free(file_path);
    allocator.free(cwd_path);
    std.process.argsFree(allocator, args);
    // Initialize our application
    var app = try Flow.init(allocator, file_path);
    defer app.deinit();
    // Run the application
    try app.run();
}

test "refAllDecls" {
    @import("std").testing.refAllDecls(@This());
}
