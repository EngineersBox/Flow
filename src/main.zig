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

    // Initialize our application
    var app = try Flow.init(allocator);
    defer app.deinit();

    // Run the application
    try app.run();
}
