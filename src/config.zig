const std = @import("std");

spaces_per_tab: usize,

pub const default: @This() = .{
    .spaces_per_tab = 4,
};
