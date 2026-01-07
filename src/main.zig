const std = @import("std");
const ncz = @import("notcurses.zig");
const nc = ncz.nc;
const pc = @import("piecechain.zig").pc;
const ts = @import("tree-sitter");
const Config = @import("config.zig");
const known_folders = @import("known-folders");

pub const known_folders_config: known_folders.KnownFolderConfig = .{
    .xdg_force_default = false,
    .xdg_on_mac = true,
};

pub fn main() !void {
    var gpa_creator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_creator.deinit() == .ok);
    const gpa = gpa_creator.allocator();

    const parser = ts.Parser.create();
    defer parser.destroy();

    const config: Config = try Config.fromKnownLocationsOrDefault(gpa);
    std.debug.print("Spaces per tab: {d}\n", .{ config.spaces_per_tab });

    const chain: *pc.struct_PieceChain_t = pc.piece_chain_open("test.txt").?;
    std.debug.print("Opened piece chain\n", .{});
    defer pc.piece_chain_destroy(chain);
    _ = pc.piece_chain_insert(chain, 5, " more", 5);
    std.debug.print("Inserted data\n", .{});
    const iter: *pc.struct_PieceChainIterator_t = pc.piece_chain_iter(chain, 0, pc.piece_chain_size(chain)).?;
    defer pc.piece_chain_iter_free(iter);
    std.debug.print("Iterating\n", .{});
    var data: [*c]const u8 = null;
    var len: usize = 0;
    while (pc.piece_chain_iter_next(iter, &data, &len)) {
        std.debug.print("Data: {s}\n", .{ data[0..len] });
    }
    std.debug.print("Done\n", .{});

    var nc_opts: nc.notcurses_options = ncz.default_notcurses_options;
    const ncs: *nc.notcurses = (nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed"));
    defer _ = nc.notcurses_stop(ncs);
}
