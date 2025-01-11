const std = @import("std");
const zts = @import("zts");

pub const TreeSitter = struct {
    language: *const zts.Language,
    parser: *zts.Parser,
    tree: ?zts.Tree,

    pub fn init(language: zts.LanguageGrammar) !TreeSitter {
        return .{
            .language = try zts.loadLanguage(language),
            .parser = try zts.Parser.init(),
            .tree = null,
        };
    }

    pub fn deinit(self: *TreeSitter) void {
        self.parser.deinit();
    }

    pub fn parseBuffer(self: *TreeSitter, buffer: []const u8) !void {
        self.tree = try self.parser.parse(self.tree, buffer);
    }
};
