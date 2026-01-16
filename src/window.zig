const std = @import("std");
const Buffer = @import("buffer.zig");
const ncz = @import("external/notcurses.zig");
const nc = ncz.nc;

plane: nc.ncplane,
buffer: ?*Buffer,

pub const BufferInitError = error{
    FailedToGetStdPlane,
    FailedPlaneCreation,
};

pub fn init(notcurses: *nc.notcurses, parent_plane: ?*nc.ncplane) BufferInitError!@This() {
    if (parent_plane == null) {
        parent_plane = nc.notcurses_stdplane(notcurses) orelse return BufferInitError.FailedToGetStdPlane;
    }
    return .{
        .plane = nc.ncplane_create(parent_plane, ncz.default_ncplane_options) orelse return BufferInitError.FailedPlaneCreation,
        .buffer = null,
    };
}
// Does not free attached buffer
pub fn deinit(self: @This()) void {
    nc.ncplane_destroy(self.plane);
}

pub fn attach_buffer(self: @This(), buffer: *Buffer) void {
    self.buffer = buffer;
}

pub fn detach_buffer(self: @This()) ?*Buffer {
    const buffer: *Buffer = self.buffer;
    self.buffer = null;
    return buffer;
}

