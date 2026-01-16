const std = @import("std");
const Allocator = std.mem.Allocator;

const Buffer = @import("buffer.zig");
const Window = @import("window.zig");
const Config = @import("config.zig");
const Logging = @import("logging.zig");

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

gpa: Allocator,
config: Config,
logger: Logging.Logger,
ncs: *nc.notcurses,
stdplane: *nc.ncplane,

pub fn new(gpa: Allocator, config: Config, ncs: *nc.notcurses) !@This() {
    const stdplane: *nc.ncplane = nc.notcurses_stdplane(ncs) orelse return error.FailedStdplaneCreation;
    const log_file_path: []const u8 = Logging.standard_log_file(gpa, "flow.log");
    // defer gpa.free(log_file_path);
    const logger = try Logging.Logger.init(
        gpa,
        log_file_path,
        stdplane,
    );
    return .{
        .gpa = gpa,
        .config = config,
        .logger = logger,
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

pub fn deinit(self: *@This()) !void {
    self.config.deinit(self.gpa);
    try self.logger.deinit();
}

fn update(_: @This()) !void {

}

pub fn run(self: @This()) void {
    defer _ = nc.notcurses_stop(self.ncs);
    while (!state.should_close) {
        self.update() catch |err| {
            // TODO: Deal with this properly, have some error
            //       log functions that both show a visual
            //       marker and description of the error and
            //       log to a file as well.
            std.log.err("ERROR: {s}\n", .{ @errorName(err) });
        };
        _ = nc.notcurses_render(self.ncs);
    }
}
