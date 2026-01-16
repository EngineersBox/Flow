const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("buffer.zig");
const Window = @import("window.zig");
const Config = @import("config.zig");

const ncz = @import("external/notcurses.zig");
const nc = ncz.nc;

const State = struct {
    should_close: bool = false,
};
var state: State = .{};

fn sig_handler(_: c_int) callconv(.c) void {
    state.should_close = true;
}

const AppInitError = error {
    SignalHandlerRegistration
};

config: Config,
gpa: Allocator,
ncs: *nc.notcurses,
stdplane: *nc.ncplane,

pub fn new(gpa: Allocator, config: Config, ncs: *nc.notcurses) error{FailedStdplaneCreation}!@This() {
    const stdplane: *nc.ncplane = nc.notcurses_stdplane(ncs) orelse return error.FailedStdplaneCreation;
    return .{
        .gpa = gpa,
        .config = config,
        .ncs = ncs,
        .stdplane = stdplane,
    };
}

pub fn init(_: @This()) AppInitError!void {
    const action = std.c.Sigaction {
        .handler = .{ .handler = sig_handler, },
        .mask = 0,
        .flags = 0,
    };
    if (std.c.sigaction(std.c.SIG.INT, &action, null) != 0) {
        return AppInitError.SignalHandlerRegistration;
    }
    if (std.c.sigaction(std.c.SIG.INT, &action, null) != 0) {
        return AppInitError.SignalHandlerRegistration;
    }
    if (std.c.sigaction(std.c.SIG.INT, &action, null) != 0) {
        return AppInitError.SignalHandlerRegistration;
    }
}

pub fn deinit(self: @This()) void {
    self.config.deinit(self.gpa);
}

fn update(_: @This()) !void {

}

pub fn run(self: @This()) void {
    defer _ = nc.notcurses_stop(self.ncs);
    while (!state.should_close) {
        self.update() catch |err| {
            std.log.err("ERROR: {s}\n", .{ @errorName(err) });
        };
        _ = nc.notcurses_render(self.ncs);
    }
}
