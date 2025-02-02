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

    raw_ptr: *anyopaque,
    ptr: [*]align(std.mem.page_size) u8,
    len: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, fd: std.fs.File) !MmapPager {
        const stats = try fd.stat();
        if (stats.size > MaxFileSize) {
            return error.FileTooLarge;
        }
        // TODO: Refactor to reserve a MAP_ANONYMOUS continuous space of 8 GB
        //       and then mmap sections of the file into it.

        // Create a contiguous virtual address space over the file
        // with space for expansion
        const ptr = std.c.mmap(
            null,
            MaxFileSize,
            std.c.PROT.READ | std.c.PROT.EXEC,
            std.c.MAP{
                .TYPE = .SHARED,
            },
            fd.handle,
            0,
        );
        return .{
            .raw_ptr = ptr,
            .ptr = @as([*]align(std.mem.page_size) u8, @ptrCast(@alignCast(ptr))),
            .len = @as(u64, stats.size),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MmapPager) void {
        _ = std.c.munmap(@alignCast(self.raw_ptr), self.len);
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
                try std.os.madvise(@as([*]u8, start), size, std.c.MADV.WILLNEED);
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
        const rc: c_int = std.c.msync(self.ptr, self.len, 0);
        if (rc != 0) {
            return error.MsyncFailed;
        }
    }
};
