const std = @import("std");

pub fn ConcurrentSinglyLinkedList(comptime T: type) type {
    return struct {
        pub const Node = std.SinglyLinkedList(T).Node;

        rwlock: std.Thread.RwLock,
        singly_linked_list: std.SinglyLinkedList(T),

        pub fn init() @This() {
            return .{
                .rwlock = .{},
                .singly_linked_list = .{},
            };
        }

        pub fn prepend(self: *@This(), node: *Node) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.singly_linked_list.prepend(node);
        }

        pub fn remove(self: *@This(), node: *Node) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.singly_linked_list.remove(node);
        }

        pub fn popFirst(self: *@This()) ?*Node {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            return self.singly_linked_list.popFirst();
        }

        pub fn len(self: *@This()) usize {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            return self.singly_linked_list.len();
        }
    };
}
