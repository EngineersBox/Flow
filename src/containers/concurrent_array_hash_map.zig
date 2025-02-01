const std = @import("std");

pub fn ConcurrentArrayHashMap(comptime K: type, comptime V: type, comptime Context: type, comptime store_hash: bool) type {
    return struct {
        allocator: std.mem.Allocator,
        rwlock: std.Thread.RwLock,
        map: std.ArrayHashMap(K, V, Context, store_hash),

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{
                .allocator = allocator,
                .rwlock = .{},
                .map = std.ArrayHashMap(K, V, Context, store_hash).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.deinit();
        }

        pub fn get(self: *@This(), key: K) ?V {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.get(key);
        }

        pub fn tryGet(self: *@This(), key: K) struct { value: ?V, aquired: bool } {
            if (!self.rwlock.tryLockShared()) {
                return .{
                    .value = null,
                    .aquired = false,
                };
            }
            defer self.rwlock.unlockShared();
            return .{ .value = self.map.get(key), .aquired = true };
        }

        pub fn put(self: *@This(), key: K, value: V) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.put(key, value);
        }

        pub fn tryPut(self: *@This(), key: K, value: V) bool {
            if (!self.rwlock.tryLock()) {
                return false;
            }
            defer self.rwlock.unlock();
            self.map.put(key, value);
            return true;
        }

        pub fn count(self: *@This()) usize {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.map.count();
        }

        pub fn tryCount(self: *@This()) struct { count: usize, aquired: bool } {
            if (!self.rwlock.tryLockShared()) {
                return .{
                    .count = 0,
                    .aquired = false,
                };
            }
            self.rwlock.unlockShared();
            return self.map.count();
        }

        pub fn iterator(self: *@This()) Iterator {
            return Iterator.init(&self.map, &self.rwlock);
        }

        pub const Iterator = struct {
            iter: std.ArrayHashMap(K, V, Context, store_hash).Iterator,
            rwlock: *std.Thread.RwLock,

            pub fn init(map: *std.ArrayHashMap(K, V, Context, store_hash), rwlock: *std.Thread.RwLock) @This() {
                rwlock.lockShared();
                return .{
                    .iter = map.iterator(),
                    .rwlock = rwlock,
                };
            }

            pub fn next(self: *@This()) ?std.ArrayHashMap(K, V, Context, store_hash).Entry {
                if (self.iter.next()) |entry| {
                    return entry;
                }
                self.rwlock.unlockShared();
                return null;
            }
        };
    };
}
