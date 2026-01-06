const std = @import("std");
const ncz = @import("notcurses.zig");
const nc = ncz.nc;

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    var nc_opts: nc.notcurses_options = ncz.default_notcurses_options;
    const ncs: *nc.notcurses = (nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed"));
    defer _ = nc.notcurses_stop(ncs);
}
