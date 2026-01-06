module notcurses;
import libc;

extern fn uint htole(uint) @cname("compat_htole");
extern fn int wcwidth(libc::WChar c) @cname("compat_wcwidth");
extern fn int wcswidth(libc::WChar* s, usz c) @cname("compat_wcswidth");
