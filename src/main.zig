const std = @import("std");
const ncz = @import("notcurses.zig");
const nc = ncz.nc;
const pc = @import("piecechain.zig").pc;
const ts = @import("tree-sitter");
const ts_zig = @import("ts-lang-zig");
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

    // Tree sitter
    const parser = ts.Parser.create();
    try parser.setLanguage(@as(*const ts.Language,@ptrCast(ts_zig.language())));
    defer parser.destroy();

    // Config
    const config: Config = try Config.fromKnownLocationsOrDefault(gpa);
    std.debug.print("Spaces per tab: {d}\n", .{ config.spaces_per_tab });

    // Piece chain
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

    // Notcurses
    _ = std.c.setlocale(std.c.LC.ALL, "");
    var nc_opts: nc.notcurses_options = ncz.default_notcurses_options;
    const ncs: *nc.notcurses = nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed");
    const stdplane: *nc.struct_ncplane = nc.notcurses_stdplane(ncs) orelse @panic("Failed to create stdplane");
    defer nc.ncplane_destroy(stdplane);
    _ = nc.ncplane_set_bg_rgb(stdplane, 0x00FF00);
    _ = nc.ncplane_set_bg_alpha(stdplane, nc.NCALPHA_OPAQUE);
    const childplane: *nc.struct_ncplane = nc.ncplane_create(
        stdplane,
        &nc.ncplane_options{
            .y = 10,
            .x = 5,
            .rows = 5,
            .cols = 10,
            .userptr = null,
            .name = null,
            .resizecb = null,
            .flags = nc.NCPLANE_OPTION_FIXED,
            .margin_b = 0,
            .margin_r = 0,
        },
    ) orelse @panic("Failed to create child plane");
    _ = nc.ncplane_set_bg_rgb(childplane, 0xFF0000);
    _ = nc.ncplane_set_bg_alpha(childplane, nc.NCALPHA_OPAQUE);
    _ = nc.ncplane_putstr(childplane, "tester");
    nc.ncplane_move_top(childplane);
    defer nc.ncplane_destroy(childplane);
    while (true) {
        _ = nc.notcurses_render(ncs);
        // std.Thread.sleep(5_000_000);
    }
    std.Thread.sleep(2);
    defer _ = nc.notcurses_stop(ncs);
}
