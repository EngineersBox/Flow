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

fn colour_bg(channels: *u64, r: c_uint, g: c_uint, b: c_uint, a: c_uint) void {
    _ = nc.ncchannels_set_bg_rgb8(channels, r, g, b);
    _ = nc.ncchannels_set_bg_alpha(channels, a);
}

fn colour_fg(channels: *u64, r: c_uint, g: c_uint, b: c_uint, a: c_uint) void {
    _ = nc.ncchannels_set_fg_rgb8(channels, r, g, b);
    _ = nc.ncchannels_set_fg_alpha(channels, a);
}

pub fn main() !void {
    var gpa_creator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa_creator.deinit() == .ok);
    const gpa = gpa_creator.allocator();

    // Config
    const config: Config = try Config.fromKnownLocationsOrDefault(gpa);
    std.debug.print("Spaces per tab: {d}\n", .{config.spaces_per_tab});

    // Tree sitter
    const parser = ts.Parser.create();
    try parser.setLanguage(@as(*const ts.Language, @ptrCast(ts_zig.language())));
    defer parser.destroy();

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
        std.debug.print("Data: {s}\n", .{data[0..len]});
    }
    std.debug.print("Done\n", .{});

    // Notcurses
    _ = std.c.setlocale(std.c.LC.ALL, "");
    var nc_opts: nc.notcurses_options = ncz.default_notcurses_options;
    const ncs: *nc.notcurses = nc.notcurses_core_init(&nc_opts, null) orelse @panic("notcurses_core_init() failed");
    const stdplane: *nc.struct_ncplane = nc.notcurses_stdplane(ncs) orelse @panic("Failed to create stdplane");
    defer nc.ncplane_destroy(stdplane);

    const tabbed_plane: *nc.struct_ncplane = nc.ncplane_create(
        stdplane,
        &.{
            .y = 0,
            .x = 0,
            .rows = 100, // nc.ncplane_dim_y(stdplane),
            .cols = 100, // nc.ncplane_dim_x(stdplane),
            .userptr = null,
            .name = "buffers",
            .resizecb = null,
            .flags = nc.NCPLANE_OPTION_FIXED,
            .margin_b = 0,
            .margin_r = 0,
        },
    ) orelse @panic("Failed to create tabbed plane");
    defer nc.ncplane_destroy(tabbed_plane);
    var tabbed_opts: nc.struct_nctabbed_options = .{
        .selchan = 0,
        .hdrchan = 0,
        .sepchan = 0,
        .separator = "|",
        .flags = 0,
    };
    colour_bg(&tabbed_opts.selchan, 176, 74, 77, nc.NCALPHA_OPAQUE);
    colour_bg(&tabbed_opts.hdrchan, 20, 20, 20, nc.NCALPHA_OPAQUE);
    const tabbed: *nc.struct_nctabbed = nc.nctabbed_create(
        tabbed_plane,
        &tabbed_opts,
    ) orelse @panic("Failed to create tabbed");
    defer nc.nctabbed_destroy(tabbed);
    const tab: *nc.nctab = nc.nctabbed_add(
        tabbed,
        null,
        null,
        // Interesting method for anonymous functions. Note that they can be stateful
        struct {
            fn cb(_: ?*nc.nctab, _: ?*nc.ncplane, _: ?*anyopaque) callconv(.c) void {
                // Do nothing
            }
        }.cb,
        "tab",
        null,
    ) orelse @panic("Failed to add tab");
    defer nc.nctabbed_del(tabbed, tab);
    const tab2: *nc.nctab = nc.nctabbed_add(
        tabbed,
        tab,
        null,
        struct {
            fn cb(_: ?*nc.nctab, _: ?*nc.ncplane, _: ?*anyopaque) callconv(.c) void {
                // Do nothing
            }
        }.cb,
        "tab2",
        null,
    ) orelse @panic("Failed to add tab2");
    defer nc.nctabbed_del(tabbed, tab2);
    _ = nc.nctabbed_select(tabbed, tab);
    nc.nctabbed_ensure_selected_header_visible(tabbed);
    nc.nctabbed_redraw(tabbed);

    // const childplane: *nc.struct_ncplane = nc.ncplane_create(
    //     stdplane,
    //     &nc.ncplane_options{
    //         .y = 10,
    //         .x = 5,
    //         .rows = 5,
    //         .cols = 10,
    //         .userptr = null,
    //         .name = null,
    //         .resizecb = null,
    //         .flags = nc.NCPLANE_OPTION_FIXED,
    //         .margin_b = 0,
    //         .margin_r = 0,
    //     },
    // ) orelse @panic("Failed to create child plane");
    // var base_cell: nc.struct_nccell = .{};
    // _ = nc.ncplane_base(childplane, &base_cell);
    // colour_fg(
    //     &base_cell.channels,
    //     0xFF,
    //     0x00,
    //     0xff,
    //     nc.NCALPHA_OPAQUE,
    // );
    // _ = nc.ncplane_set_base_cell(childplane, &base_cell);
    // nc.ncplane_erase(childplane);
    // _ = nc.ncplane_putstr(childplane, "tester");
    // defer nc.ncplane_destroy(childplane);
    while (true) {
        _ = nc.notcurses_render(ncs);
    }
    std.Thread.sleep(2);
    defer _ = nc.notcurses_stop(ncs);
}
