const std = @import("std");

pub const MmapPager: type = struct {

    pub const PageSize: u64 = 4 * 1024;

    ptr: []align(std.mem.page_size) u8,
    len: u64,
    allocator: *std.mem.Allocator,

    pub fn init(fd: std.os.fd_t, allocator: *std.mem.Allocator) !MmapPager {
        var stats = try std.os.fstat(fd);
        var ptr = try std.os.mmap(
            null,
            @intCast(usize, stats.size),
            std.os.PROT_READ | std.os.PROT_WRITE,
            std.os.MAP_SHARED,
            fd,
            0
        );
        return .{
            .ptr = ptr,
            .len = @intCast(u64, stats.size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MmapPager) void {
        std.os.munmap(self.ptr);
        self.ptr = undefined;
        self.len = 0;
    }

};

