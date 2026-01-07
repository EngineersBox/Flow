const std = @import("std");

pub const Query = std.ArrayList(u8);
pub const Tag = std.ArrayList(u8);
pub const Tags = std.ArrayList(Tag);
const QueryContext = struct {
    pub fn hash(self: @This(), s: Query) u32 {
        _ = self;
        return std.array_hash_map.hashString(s.items);
    }
    pub fn eql(self: @This(), a: Query, b: Query, b_index: usize) bool {
        _ = self;
        _ = b_index;
        return std.array_hash_map.eqlString(a.items, b.items);
    }
};
const Elems = std.ArrayHashMap(Query, Tags, QueryContext, true);

pub const Queries = struct {
    allocator: std.mem.Allocator,
    buffer: []const u8,
    elems: Elems,

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8) @This() {
        return .{
            .allocator = allocator,
            .buffer = buffer,
            .elems = Elems.init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        var iter = self.elems.iterator();
        while (iter.next()) |entry| {
            entry.key_ptr.*.deinit();
            for (entry.value_ptr.items) |tag| {
                tag.deinit();
            }
            entry.value_ptr.deinit();
        }
        self.elems.deinit();
    }

    pub fn parseQueries(self: *@This()) !void {
        // { or }
        var brace_level: usize = 0;
        // [ or ]
        var bracket_level: usize = 0;
        // ( or )
        var parenthesis_level: usize = 0;
        var match_stack = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer match_stack.clearAndFree();
        var tag_stack = try Tags.initCapacity(self.allocator, 0);
        defer {
            while (tag_stack.pop()) |tag| {
                tag.deinit();
            }
            tag_stack.deinit();
        }
        var parsing_tag: bool = false;
        var query: ?Query = null;
        errdefer {
            if (query) |q| {
                q.deinit();
            }
        }
        var comment: bool = false;
        var string: bool = false;
        for (self.buffer, 0..) |char, i| {
            if (query == null) {
                // Prevents creating a new query at the end without it
                // being stored in the map
                query = Query.init(self.allocator);
            }
            if (comment) {
                if (char == '\n') {
                    comment = false;
                }
                continue;
            } else if (string) {
                if (char == '"') {
                    string = false;
                }
                try query.?.append(char);
                continue;
            }
            switch (char) {
                ';' => {
                    comment = true;
                    continue;
                },
                '"' => {
                    string = true;
                },
                '{' => {
                    try match_stack.append(char);
                    brace_level += 1;
                    parsing_tag = false;
                },
                '}' => {
                    const matching = match_stack.pop() orelse {
                        std.log.err("Unmatched '}}' @ {d}, has no opening partner on the stack", .{i});
                        return error.TrailingUnmatchedBrace;
                    };
                    if (matching != '{') {
                        std.log.err("Missing matching '{{' for '}}' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                        return error.NoMatchingBrace;
                    }
                    brace_level -= 1;
                    parsing_tag = false;
                    // try query.?.append(char);
                },
                '[' => {
                    try match_stack.append(char);
                    bracket_level += 1;
                    parsing_tag = false;
                },
                ']' => {
                    const matching = match_stack.pop() orelse {
                        std.log.err("Unmatched ']' @ {d}, has no opening partner on the stack", .{i});
                        return error.TrailingUnmatchedBracket;
                    };
                    if (matching != '[') {
                        std.log.err("Missing matching '[' for ']' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                        return error.NoMatchingBracket;
                    }
                    bracket_level -= 1;
                    parsing_tag = false;
                    // try query.?.append(char);
                },
                '(' => {
                    try match_stack.append(char);
                    parenthesis_level += 1;
                    parsing_tag = false;
                },
                ')' => {
                    const matching = match_stack.pop() orelse {
                        std.log.err("Unmatched ')' @ {d}, has no opening partner on the stack", .{i});
                        return error.TrailingUnmatchedParenthesis;
                    };
                    if (matching != '(') {
                        std.log.err("Missing matching '(' for ')' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                        return error.NoMatchingParenthesis;
                    }
                    parenthesis_level -= 1;
                    parsing_tag = false;
                    // try query.?.append(char);
                },
                '@' => {
                    if (parsing_tag) {
                        return error.InvalidTagPlacement;
                    }
                    // Don't add the leading '@' to a tag since we need
                    // to remove it later anyway
                    try tag_stack.append(try Tag.initCapacity(self.allocator, 0));
                    parsing_tag = true;
                },
                0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2E => {
                    if (parsing_tag) {
                        try tag_stack.items[tag_stack.items.len - 1].append(char);
                    }
                },
                else => {
                    parsing_tag = false;
                },
            }
            if (char != '\n') {
                try query.?.append(char);
            }
            if (char == '\n' and bracket_level == 0 and bracket_level == 0 and parenthesis_level == 0 and !parsing_tag and tag_stack.items.len > 0) {
                const result = try self.elems.getOrPut(query.?);
                if (!result.found_existing) {
                    result.value_ptr.* = try Tags.initCapacity(self.allocator, 0);
                }
                while (tag_stack.pop()) |tag| {
                    try result.value_ptr.append(tag);
                }
                query = null;
            }
            continue;
        }
        if (match_stack.items.len != 0) {
            return error.NonEmptyMatchStack;
        }
        // var iter = self.elems.iterator();
        // while (iter.next()) |entry| {
        //     std.log.err("Key: {s} Value count: {d}", .{ entry.key_ptr.items, entry.value_ptr.items.len });
        //     for (entry.value_ptr.items, 0..) |value, i| {
        //         std.log.err(" - Value {d}: {s}", .{ i, value.items });
        //     }
        // }
    }
};
