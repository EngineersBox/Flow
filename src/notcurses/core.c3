module notcurses;
import libc;

extern fn ZString version() @cname("notcurses_version");
<*
 @param [&out] major
 @param [&out] minor
 @param [&out] patch
 @param [&out] tweak
*>
extern fn void version_components(int* major, int* minor, int* patch, int* tweak) @cname("notcurses_version_components");

typedef NotCurses = void;
typedef Plane = void;
typedef Visual = void;
typedef UPlot = void;
typedef DPlot = void;
typedef ProgBar = void;
typedef FdPlane = void;
typedef SubProc = void;
typedef Selector = void;
typedef MultiSelector = void;
typedef Reader = void;
typedef FadeCtx = void;
typedef Tablet = void;
typedef Reel = void;
typedef Tab = void;
typedef Tabbed = void;
typedef Direct = void;

enum Blitter: const CInt @cname("ncblitter_e") {
    DEFAULT = 0,
    BLIT_1X1 = 1,
    BLIT_2X1 = 2,
    BLIT_2X2 = 3,
    BLIT_3X2 = 4,
    BLIT_4X2 = 5,
    BRAILLE = 6,
    PIXEL = 7,
    BLIT_4X1 = 8,
    BLIT_8X1 = 9
}

enum Align: const CInt @cname("ncalign_e") {
    UNALIGNED = 0,
    LEFT = 1,
    CENTRE = 2,
    RIGHT = 3
}

const CInt ALIGN_TOP = (CInt) Align.LEFT;
const CInt ALIGN_BOTTOM = (CInt) Align.RIGHT;

enum Scale: const CInt @cname("ncscale_e") {
    NONE = 0,
    SCALE = 1,
    STRETCH = 2,
    NONE_HIRES = 3,
    SCALE_HIRES = 4
}

const usz WCHAR_MAX_UTF8BYTES = 4;

<*
 @require egcs != null
 @param [&out] validbytes
 @param [&out] validwidth
*>
extern fn int str_width(ZString egcs, int* validbytes, int* validwidth) @cname("ncstrwidth");

<*
 @require ucs32 != null
 @require result_buf != null
 @param [&in] ucs32
 @param [&out] result_buf
*>
extern fn int ucs32_to_utf8(
    uint* ucs32,
    uint ucs32_count,
    char* result_buf,
    usz buflen
) @cname("notcurses_ucs32_to_utf8");

struct Cell @cname("nccell") {
    uint gcluster;
    char gcluster_backstop;
    char width;
    ushort stylemask;
    ulong channels;
}

macro Cell cell_initializer(libc::WChar c, ushort stylemask, uint channels) {
    return (Cell) {
        .gcluster = htole(c),
        .gcluster_backstop = 0,
        .width = (char)((wcwidth(c) < 0 || !c) ? 1 : wcwidth(c)),
        .stylemask = s,
        .channels = channels
    };
}

macro Cell cell_char_initializer(libc::WChar c) {
    return Cell.cell_initializer(c, 0, 0);
}

macro Cell cell_trivial_initializer() {
    return (Cell) {
        .gcluster = 0,
        .gcluster_backstop = 0,
        .width = 1,
        .stylemask = 0,
        .channels = 0 
    };
}

macro void Cell.init(Cell* self) {
    std::core::mem::clear(self, Cell.sizeof);
}

extern fn int Plane.load_cell(Plane* self, Cell* c, ZString gcluster) @cname("nccell_load");

fn int Plane.prime_cell(Plane* self, Cell* c, ZString gcluster, ushort stylemask, ulong channels) {
    c.stylemask = stylemask;
    c.channels = channels;
    return self.load_cell(c, gcluster);
}

extern fn int Plane.duplicate_cell(Plane* self, Cell* target, Cell* c) @cname("nccell_duplicate");
extern fn void Plane.release_cell(Plane* self, Cell* c) @cname("nccell_release");

const ushort STYLE_MASK = 0xffff;
const ushort STYLE_ITALIC = 0x0010;
const ushort STYLE_UNDERLINE = 0x0008;
const ushort STYLE_UNDERCURL = 0x0004;
const ushort STYLE_BOLD = 0x0002;
const ushort STYLE_STRUCK = 0x0001;
const ushort STYLE_NONE = 0;

macro void Cell.set_styles(Cell* self, uint stylebits) {
    c.stylemask = stylebits & STYLE_MASK;
}

macro ushort Cell.styles(Cell* self) {
    return c.stylemask;
}

macro void Cell.on_styles(Cell* self, uint stylebits) {
    c.stylemask |= (ushort)(stylebits & STYLE_MASK);
}

macro void Cell.off_styles(Cell* self, uint stylebits) {
    c.stylemask &= (ushort)~(stylebits & STYLE_MASK);
}

macro void Cell.set_fg_default(Cell* self) {
    channels_set_fg_default(&c.channels);
}

macro void Cell.set_bg_default(Cell* self) {
    channels_set_bg_default(&c.channels);
}

    extern fn Cell.set_fg_alpha(Cell* self, uint alpha) @cname("nccell_set_fg_alpha")
