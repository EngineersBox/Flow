module notcurses::keys;

const usz PRETERUNICODEBASE = 1115000;
macro usz preterunicode(usz $w) {
    return $w + PRETERUNICODEBASE;
}

// Special composed key definitions. These values are added to 0x100000.
const usz INVALID = preterunicode(0);
const usz RESIZE = preterunicode(1); // we received SIGWINCH
const usz UP = preterunicode(2);
const usz RIGHT = preterunicode(3);
const usz DOWN = preterunicode(4);
const usz LEFT = preterunicode(5);
const usz INS = preterunicode(6);
const usz DEL = preterunicode(7);
const usz BACKSPACE = preterunicode(8); // backspace (sometimes)
const usz PGDOWN = preterunicode(9);
const usz PGUP = preterunicode(10);
const usz HOME = preterunicode(11);
const usz END = preterunicode(12);
const usz F00 = preterunicode(20);
const usz F01 = preterunicode(21);
const usz F02 = preterunicode(22);
const usz F03 = preterunicode(23);
const usz F04 = preterunicode(24);
const usz F05 = preterunicode(25);
const usz F06 = preterunicode(26);
const usz F07 = preterunicode(27);
const usz F08 = preterunicode(28);
const usz F09 = preterunicode(29);
const usz F10 = preterunicode(30);
const usz F11 = preterunicode(31);
const usz F12 = preterunicode(32);
const usz F13 = preterunicode(33);
const usz F14 = preterunicode(34);
const usz F15 = preterunicode(35);
const usz F16 = preterunicode(36);
const usz F17 = preterunicode(37);
const usz F18 = preterunicode(38);
const usz F19 = preterunicode(39);
const usz F20 = preterunicode(40);
const usz F21 = preterunicode(41);
const usz F22 = preterunicode(42);
const usz F23 = preterunicode(43);
const usz F24 = preterunicode(44);
const usz F25 = preterunicode(45);
const usz F26 = preterunicode(46);
const usz F27 = preterunicode(47);
const usz F28 = preterunicode(48);
const usz F29 = preterunicode(49);
const usz F30 = preterunicode(50);
const usz F31 = preterunicode(51);
const usz F32 = preterunicode(52);
const usz F33 = preterunicode(53);
const usz F34 = preterunicode(54);
const usz F35 = preterunicode(55);
const usz F36 = preterunicode(56);
const usz F37 = preterunicode(57);
const usz F38 = preterunicode(58);
const usz F39 = preterunicode(59);
const usz F40 = preterunicode(60);
const usz F41 = preterunicode(61);
const usz F42 = preterunicode(62);
const usz F43 = preterunicode(63);
const usz F44 = preterunicode(64);
const usz F45 = preterunicode(65);
const usz F46 = preterunicode(66);
const usz F47 = preterunicode(67);
const usz F48 = preterunicode(68);
const usz F49 = preterunicode(69);
const usz F50 = preterunicode(70);
const usz F51 = preterunicode(71);
const usz F52 = preterunicode(72);
const usz F53 = preterunicode(73);
const usz F54 = preterunicode(74);
const usz F55 = preterunicode(75);
const usz F56 = preterunicode(76);
const usz F57 = preterunicode(77);
const usz F58 = preterunicode(78);
const usz F59 = preterunicode(79);
const usz F60 = preterunicode(80);
// ... leave room for up to 100 function keys, egads
const usz ENTER = preterunicode(121);
const usz CLS = preterunicode(122); // "clear-screen or erase"
const usz DLEFT = preterunicode(123); // down + left on keypad
const usz DRIGHT = preterunicode(124);
const usz ULEFT = preterunicode(125); // up + left on keypad
const usz URIGHT = preterunicode(126);
const usz CENTER = preterunicode(127); // the most truly neutral of keypresses
const usz BEGIN = preterunicode(128);
const usz CANCEL = preterunicode(129);
const usz CLOSE = preterunicode(130);
const usz COMMAND = preterunicode(131);
const usz COPY = preterunicode(132);
const usz EXIT = preterunicode(133);
const usz PRINT = preterunicode(134);
const usz REFRESH = preterunicode(135);
const usz SEPARATOR = preterunicode(136);
// these keys aren't generally available outside of the kitty protocol
const usz CAPS_LOCK = preterunicode(150);
const usz SCROLL_LOCK = preterunicode(151);
const usz NUM_LOCK = preterunicode(152);
const usz PRINT_SCREEN = preterunicode(153);
const usz PAUSE = preterunicode(154);
const usz MENU = preterunicode(155);
// media keys, similarly only available through kitty's protocol
const usz MEDIA_PLAY = preterunicode(158);
const usz MEDIA_PAUSE = preterunicode(159);
const usz MEDIA_PPAUSE = preterunicode(160);
const usz MEDIA_REV = preterunicode(161);
const usz MEDIA_STOP = preterunicode(162);
const usz MEDIA_FF = preterunicode(163);
const usz MEDIA_REWIND = preterunicode(164);
const usz MEDIA_NEXT = preterunicode(165);
const usz MEDIA_PREV = preterunicode(166);
const usz MEDIA_RECORD = preterunicode(167);
const usz MEDIA_LVOL = preterunicode(168);
const usz MEDIA_RVOL = preterunicode(169);
const usz MEDIA_MUTE = preterunicode(170);
// modifiers when pressed by themselves. this ordering comes from the Kitty
// keyboard protocol, and mustn't be changed without updating handlers.
const usz LSHIFT = preterunicode(171);
const usz LCTRL = preterunicode(172);
const usz LALT = preterunicode(173);
const usz LSUPER = preterunicode(174);
const usz LHYPER = preterunicode(175);
const usz LMETA = preterunicode(176);
const usz RSHIFT = preterunicode(177);
const usz RCTRL = preterunicode(178);
const usz RALT = preterunicode(179);
const usz RSUPER = preterunicode(180);
const usz RHYPER = preterunicode(181);
const usz RMETA = preterunicode(182);
const usz L3SHIFT = preterunicode(183);
const usz L5SHIFT = preterunicode(184);
// mouse events. We encode which button was pressed into the char32_t,
// but position information is embedded in the larger ncinput event.
const usz MOTION = preterunicode(200); // no buttons pressed
const usz BUTTON1 = preterunicode(201);
const usz BUTTON2 = preterunicode(202);
const usz BUTTON3 = preterunicode(203);
const usz BUTTON4 = preterunicode(204); // scrollwheel up
const usz BUTTON5 = preterunicode(205); // scrollwheel down
const usz BUTTON6 = preterunicode(206);
const usz BUTTON7 = preterunicode(207);
const usz BUTTON8 = preterunicode(208);
const usz BUTTON9 = preterunicode(209);
const usz BUTTON10 = preterunicode(210);
const usz BUTTON11 = preterunicode(211);

// we received SIGCONT
const usz SIGNAL = preterunicode(400);

// indicates that we have reached the end of input. any further calls
// will continute to return this immediately.
const usz EOF = preterunicode(500);

// Is this uint32_t a synthesized event?
macro bool synthesized_p(uint w) {
  return w >= PRETERUNICODEBASE && w <= NCKEY_EOF;
}


// Synonyms and aliases (so far as we're concerned)
const usz NCKEY_SCROLL_UP = BUTTON4;
const usz NCKEY_SCROLL_DOWN = BUTTON5;
const usz NCKEY_RETURN = ENTER;
const usz NCKEY_TAB = 0x09;
const usz NCKEY_ESC = 0x1b;
const usz NCKEY_SPACE = 0x20;

// Is this uint32_t from the Private Use Area in the BMP (Plane 0)?
macro bool pua_p(uint w) {
  return w >= 0xe000 && w <= 0xf8ff; // 6,400 codepoints
}

// Is this uint32_t a Supplementary Private Use Area-A codepoint?
macro bool supppuaa_p(uint w) {
  return w >= 0xf0000 && w <= 0xffffd; // 65,534 codepoints
}

// Is this uint32_t a Supplementary Private Use Area-B codepoint?
macro bool supppuab_p(uint w) {
  return w >= 0x100000 && w <= 0x10fffd; // 65,534 codepoints
}

// used with the modifiers bitmask. definitions come straight from the kitty
// keyboard protocol.
const usz MOD_SHIFT = 1;
const usz MOD_ALT = 2;
const usz MOD_CTRL = 4;
const usz MOD_SUPER = 8;
const usz MOD_HYPER = 16;
const usz MOD_META = 32;
const usz MOD_CAPSLOCK = 64;
const usz MOD_NUMLOCK = 128;
