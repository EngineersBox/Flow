const std = @import("std");
const vaxis = @import("vaxis");
const KnownFolders = @import("known-folders");
const Flow = @import("flow.zig").Flow;

pub const known_folders_config: KnownFolders.KnownFolderConfig = .{
    .xdg_force_default = false,
    .xdg_on_mac = true,
};

/// Keep our main function small. Typically handling arg parsing and initialization only
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    if (args.len < 2) {
        std.process.argsFree(allocator, args);
        std.log.err("Usage: flow <file path>\n", .{});
        return;
    }
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const file_path = try std.fs.path.resolve(allocator, &.{ cwd_path, args[1] });
    defer allocator.free(file_path);
    allocator.free(cwd_path);
    std.process.argsFree(allocator, args);
    // Initialize our application
    var app = try Flow.init(allocator, file_path);
    defer app.deinit();
    // Run the application
    try app.run();
}

test "refAllDecls" {
    @import("std").testing.refAllDecls(@This());
}

// const std = @import("std");
// const loadLanguage = @import("lang/lang.zig").loadLanguage;
// const ts = @import("tree-sitter");
//
// pub const TreeIterator = struct {
//     cursor: ts.TreeCursor,
//     vistied_children: bool,
//     yielded: bool,
//
//     pub fn init(node: ts.Node) TreeIterator {
//         return .{
//             .cursor = node.walk(),
//             .vistied_children = false,
//             .yielded = false,
//         };
//     }
//
//     pub fn deinit(self: *@This()) void {
//         self.cursor.destroy();
//     }
//
//     pub fn next(self: *@This()) ?ts.Node {
//         while (true) {
//             if (self.yielded) {
//                 self.yielded = false;
//                 if (!self.cursor.gotoFirstChild()) {
//                     self.vistied_children = true;
//                 }
//                 continue;
//             }
//             if (!self.vistied_children) {
//                 self.yielded = true;
//                 return self.cursor.node();
//             } else if (self.cursor.gotoNextSibling()) {
//                 self.vistied_children = false;
//             } else if (!self.cursor.gotoParent()) {
//                 break;
//             }
//         }
//         return null;
//     }
// };
//
// fn cb(_: ts.Parser.State) callconv(.C) bool {
//     return true;
// }
//
// pub fn main() !void {
//     const lang = try loadLanguage(.zig);
//     defer lang.destroy();
//     std.log.err("Lang ABI version: {d}", .{lang.abiVersion()});
//     std.log.err("Field count: {d}", .{lang.fieldCount()});
//     for (0..lang.fieldCount()) |i| {
//         if (lang.fieldNameForId(@intCast(i))) |name| {
//             std.log.err("Field: {s}", .{name});
//         }
//     }
//     const parser = ts.Parser.create();
//     defer parser.destroy();
//     try parser.setLanguage(lang);
//     const string: []const u8 = "pub fn main() !void {}";
//     var buffer: [6]u8 = [1]u8{0} ** 6;
//     var ctx: TSReadContext = .{
//         .value = string,
//         .return_buffer = &buffer,
//     };
//     const input = ts.Input{
//         .payload = &ctx,
//         .read = readFunc,
//         .encoding = .UTF_8,
//         .decode = null,
//     };
//     const tree = parser.parseWithOptions(
//         input,
//         null,
//         .{
//             .payload = null,
//             .progress_callback = cb,
//         },
//     ) orelse return error.ParseFailed;
//     var iter = TreeIterator.init(tree.rootNode());
//     defer iter.deinit();
//     while (iter.next()) |node| {
//         const sexp = node.toSexp();
//         defer ts.Node.freeSexp(sexp);
//         std.log.err(
//             "Start: {d} End: {d} Str: '{s}' S-Exp: '{s}'",
//             .{
//                 node.startByte(),
//                 node.endByte(),
//                 string[node.startByte()..node.endByte()],
//                 sexp,
//             },
//         );
//     }
// }
//
// const TSReadContext = struct {
//     value: []const u8,
//     return_buffer: *[6]u8,
// };
//
// fn readFunc(
//     payload: ?*anyopaque,
//     byte_index: u32,
//     _: ts.Point,
//     bytes_read: *u32,
// ) callconv(.C) [*c]const u8 {
//     const ctx: *TSReadContext = @ptrCast(@alignCast(payload));
//     if (byte_index >= ctx.value.len) {
//         bytes_read.* = 0;
//         return 0;
//     }
//     bytes_read.* = 1;
//     return @ptrCast(ctx.value[byte_index .. byte_index + 1]);
// }
