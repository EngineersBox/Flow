// Source: https://ravendb.net/articles/implementing-a-file-pager-in-zig-using-mmap
// Author: Oren Eini
const std = @import("std");

pub const Page: type = struct {
    buffer: []align(std.mem.page_size) u8,
    number_of_pages: u32,
    page: u64,
};

pub const MmapPager: type = struct {
    pub const MaxFileSize: u64 = 8 * 1024 * 1024 * 1024; // 8 GB
    pub const PageSize: u64 = std.mem.page_size;

    ptr: []align(std.mem.page_size) u8,
    len: u64,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator, fd: std.os.fd_t) !MmapPager {
        const stats = try std.os.fstat(fd);
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        // TODO: Refactor to reserve a MAP_ANONYMOUS continuous space of 8 GB
        //       and then mmap sections of the file into it.

        // Create a contiguous virtual address space over the file
        // with space for expansion
        const ptr = try std.os.mmap(null, MaxFileSize, std.os.PROT_READ | std.os.PROT_WRITE, std.os.MAP_SHARED, fd, 0);
        return .{
            .ptr = ptr,
            .len = @as(u64, stats.size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MmapPager) void {
        std.os.munmap(self.ptr);
        self.ptr = undefined;
        self.len = 0;
    }

    pub fn getBlocking(self: *MmapPager, page: u64, count: u32) !Page {
        return Page{
            .buffer = self.ptr[page * PageSize .. (page * PageSize + count * PageSize)],
            .number_of_pages = count,
            .page = page,
        };
    }

    pub fn release(self: *MmapPager, page: Page) void {
        _ = self;
        page.buffer = undefined;
        page.number_of_pages = undefined;
        page.page = undefined;
    }

    pub fn tryGet(self: *MmapPager, page: u64, count: u32) !?Page {
        const buf: []u8 = try self.allocator.alloc(u8, count);
        defer self.allocator.free(buf);
        std.mem.set(u8, buf, 0);
        const start: []u8 = self.ptr[page * PageSize ..];
        const size = count * PageSize;
        const rc: c_int = std.c.mincore(&start[0], size, &buf[0]);
        if (rc != 0) {
            return @errorFromInt(@as(u16, std.os.errno(rc)));
        }
        for (buf) |b| {
            if (b & 1 == 0) {
                try std.os.madvise(@as([*]u8, start), size, std.os.MADV_WILLNEED);
                return null; // not all in memory
            }
        }
        // can return to the caller immediately
        return try getBlocking(self, page, count);
    }

    pub fn write(self: *MmapPager, page: Page) !void {
        _ = self;
        _ = page;
        // nothing to do, the data is already written to
        // the memory map
    }

    pub fn sync(self: *MmapPager) !void {
        const rc: c_int = std.c.msync(&self.ptr[0], self.ptr.len, std.c.MS_SYNC);
        if (rc != 0) {
            return @errorFromInt(@as(u16, std.os.errno(rc)));
        }
    }
};
