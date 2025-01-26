const std = @import("std");

pub fn ConcurrentArrayList(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        rwlock: std.Thread.RwLock,
        array_list: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .rwlock = .{},
                .array_list = std.ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.array_list.deinit();
        }

        pub fn get(self: *@This(), index: usize) T {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.array_list.items[index];
        }

        pub fn tryGet(self: *@This(), index: usize) ?T {
            if (!self.rwlock.tryLockShared()) {
                return null;
            }
            defer self.rwlock.unlockShared();
            return self.array_list.items[index];
        }

        pub inline fn count(self: *@This()) usize {
            return self.array_list.items.len;
        }

        pub fn insert(self: *@This(), index: usize, value: T) !void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            try self.array_list.insert(index, value);
        }

        pub fn tryInsert(self: *@This(), index: usize, value: T) !bool {
            if (!self.rwlock.tryLock()) {
                return false;
            }
            defer self.rwlock.unlock();
            try self.array_list.insert(index, value);
            return true;
        }

        pub fn append(self: *@This(), value: T) !void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            try self.array_list.append(value);
        }

        pub fn tryAppend(self: *@This(), value: T) !bool {
            if (!self.rwlock.tryLock()) {
                return false;
            }
            defer self.rwlock.unlock();
            try self.array_list.append(value);
        }
    };
}
