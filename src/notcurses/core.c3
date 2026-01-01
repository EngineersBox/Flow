module notcurses;

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
