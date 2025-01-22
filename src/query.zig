const std = @import("std");

const Query = std.ArrayList(u8);
const Tag = std.ArrayList(u8);
const Tags = std.ArrayList(Tag);
const Elems = std.AutoHashMap(*Query, Tags);

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
    self.allocator.free(self.elems);
}

pub fn parseQueries(self: *@This()) !void {
    // { or }
    var brace_level: usize = 0;
    // [ or ]
    var bracket_level: usize = 0;
    // ( or )
    var parenthesis_level: usize = 0;
    // < or >
    var angled_level: usize = 0;
    var match_stack = std.ArrayList(u8).init(self.allocator);
    defer match_stack.clearAndFree();
    var tag_stack = Tags.init(self.allocator);
    defer {
        while (tag_stack.popOrNull()) |tag| {
            tag.deinit();
        }
        tag_stack.deinit();
    }
    var parsing_tag: bool = false;
    var query = Query.init(self.allocator);
    var comment: bool = false;
    for (self.buffer, 0..) |char, i| {
        std.log.err("CURRENT CHAR: '{s}'", .{[1]u8{char}});
        if (comment) {
            if (char == '\n') {
                comment = false;
            }
            continue;
        }
        switch (char) {
            ';' => {
                comment = true;
                continue;
            },
            '{' => {
                try match_stack.append(char);
                brace_level += 1;
                parsing_tag = false;
            },
            '}' => {
                const matching = match_stack.popOrNull() orelse {
                    std.log.err("Unmatched '}}' @ {d}, has not opening partner on the stack", .{i});
                    return error.TrailingUnmatchedBrace;
                };
                if (matching != '{') {
                    std.log.err("Missing matching '{{' for '}}' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                    return error.NoMatchingBrace;
                }
                try match_stack.append(char);
                brace_level -= 1;
                parsing_tag = false;
            },
            '[' => {
                try match_stack.append(char);
                bracket_level += 1;
                parsing_tag = false;
            },
            ']' => {
                const matching = match_stack.popOrNull() orelse {
                    std.log.err("Unmatched ']' @ {d}, has not opening partner on the stack", .{i});
                    return error.TrailingUnmatchedBracket;
                };
                if (matching != '[') {
                    std.log.err("Missing matching '[' for ']' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                    return error.NoMatchingBracket;
                }
                try match_stack.append(char);
                bracket_level -= 1;
                parsing_tag = false;
            },
            '(' => {
                try match_stack.append(char);
                parenthesis_level += 1;
                parsing_tag = false;
            },
            ')' => {
                const matching = match_stack.popOrNull() orelse {
                    std.log.err("Unmatched ')' @ {d}, has not opening partner on the stack", .{i});
                    return error.TrailingUnmatchedParenthesis;
                };
                if (matching != '(') {
                    std.log.err("Missing matching '(' for ')' at @ {d}, had {s}", .{ i, [1]u8{matching} });
                    return error.NoMatchingParenthesis;
                }
                try match_stack.append(char);
                parenthesis_level -= 1;
                parsing_tag = false;
            },
            '@' => {
                if (parsing_tag) {
                    return error.InvalidTagPlacement;
                }
                var tag = Tag.init(self.allocator);
                try tag.append('@');
                try tag_stack.append(tag);
                parsing_tag = true;
                std.log.err("Creating new tag",. {});
            },
            0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2E => {
                if (parsing_tag) {
                    var tag: Tag = tag_stack.getLast();
                    try tag.append(char);
                }
            },
            else => {
                parsing_tag = false;
            },
        }
        if (bracket_level == 0 and bracket_level == 0 and parenthesis_level == 0 and angled_level == 0) {
            const result = try self.elems.getOrPut(&query);
            if (!result.found_existing) {
                result.value_ptr.* = Tags.init(self.allocator);
            }
            while (tag_stack.popOrNull()) |tag| {
                try result.value_ptr.append(tag);
            }
            query = Query.init(self.allocator);
        } else {
            try query.append(char);
        }
        continue;
    }
    var iter = self.elems.iterator();
    while (iter.next()) |entry| {
        std.log.err("Key: {s}", .{entry.key_ptr.*.items});
        for (entry.value_ptr.items, 0..) |value, i| {
            std.log.err(" - Value {d}: {s}", .{ i, value.items });
        }
    }
}
