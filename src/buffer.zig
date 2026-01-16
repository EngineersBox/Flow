const std = @import("std");
const Allocator = std.mem.Allocator;
const File = std.fs.File;
const pc = @import("external/piecechain.zig").pc;

chain: pc.PieceChain_t,

pub const BufferInitError = error {
    FailedPieceChainInit,
} || File.OpenError;

pub fn new_from_file(gpa: Allocator, path: []const u8) BufferInitError!@This() {
    const canonicalized_path = std.fs.realpathAlloc(
        gpa,
        path,
    ) orelse @panic("Out of memory");
    defer gpa.free(canonicalized_path);
    // Check file exists
    try std.fs.openFileAbsolute(
        canonicalized_path,
        .{ .mode = .read_only },
    ).close();
    return .{
         .chain = pc.piece_chain_open(canonicalized_path) orelse return error.FailedPieceChainInit,
    };
}

pub fn deinit(self: @This()) void {
    pc.piece_chain_destroy(self.chain);
}
