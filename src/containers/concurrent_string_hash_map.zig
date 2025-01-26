const std = @import("std");

pub fn ConcurrentStringHashMap(comptime V: type) type {
    return struct {
        allocator: std.mem.Allocator,
        rwlock: std.Thread.RwLock,
        map: std.StringHashMap(V),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .rwlock = .{},
                .map = std.StringHashMap(V).init(allocator),
            };
        }
        pub fn deinit(self: *@This()) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.deinit();
        }

        pub fn get(self: *@This(), key: []const u8) ?V {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.get(key);
        }

        pub fn tryGet(self: *@This(), key: []const u8) struct { value: ?V, aquired: bool } {
            if (!self.rwlock.tryLockShared()) {
                return .{
                    .value = null,
                    .aquired = false,
                };
            }
            defer self.rwlock.unlockShared();
            return .{ .value = self.map.get(key), .aquired = true };
        }

        pub fn put(self: *@This(), key: []const u8, value: V) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.put(key, value);
        }

        pub fn tryPut(self: *@This(), key: []const u8, value: V) bool {
            if (!self.rwlock.tryLock()) {
                return false;
            }
            defer self.rwlock.unlock();
            self.map.put(key, value);
            return true;
        }

        pub fn count(self: @This()) usize {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.count();
        }

        pub fn tryCount(self: @This()) struct { count: usize, aquired: bool } {
            if (!self.rwlock.tryLockShared()) {
                return .{
                    .count = 0,
                    .aquired = false,
                };
            }
            self.rwlock.unlockShared();
            return self.map.count();
        }

        pub inline fn iterator(self: *@This()) Iterator {
            return Iterator.init(&self.map, &self.rwlock);
        }

        pub const Iterator = struct {
            iter: std.StringHashMap(V).Iterator,
            rwlock: *std.Thread.RwLock,

            pub fn init(map: *std.StringHashMap(V), rwlock: *std.Thread.RwLock) @This() {
                rwlock.lockShared();
                return .{
                    .iter = map.iterator(),
                    .rwlock = rwlock,
                };
            }

            pub fn next(self: *@This()) ?std.StringHashMap(V).Entry {
                if (self.iter.next()) |entry| {
                    return entry;
                }
                self.rwlock.unlockShared();
                return null;
            }
        };
    };
}
