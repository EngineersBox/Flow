#include "notcurses/compat.h"

#if defined(__linux__)                            // Linux
#include <wchar.h>
#include <arpa/inet.h>
#include <byteswap.h>
#elif defined(__APPLE__)                          // macOS
#include <wchar.h>
#include <arpa/inet.h>
#include <libkern/OSByteOrder.h>
#elif defined(__gnu_hurd__)                       // Hurd
#include <string.h>
#include <byteswap.h>
#elif defined(__MINGW32__)                        // Windows
#include <string.h>
#else                                             // BSDs
#include <wchar.h>
#include <arpa/inet.h>
#include <sys/endian.h>
#endif

inline __attribute__((always_inline)) uint32_t compat_htole(uint32_t x) {
#if defined(__linux__)                            // Linux
    return __bswap_32(htonl(x));
#elif defined(__APPLE__)                          // macOS
    return OSSwapInt32(htonl(x));
#elif defined(__gnu_hurd__)                       // Hurd
    return __bswap_32(htonl(x));
#elif defined(__MINGW32__)                        // Windows
    return x;
#else                                             // BSDs
    return bswap32(htonl(x)));
#endif
}

inline __attribute__((always_inline)) int compat_wcwidth(int wc) {
#if defined(__linux__)                            // Linux
    return wcwidth(wc);
#elif defined(__APPLE__)                          // macOS
    return wcwidth(wc);
#elif defined(__gnu_hurd__)                       // Hurd
    return 1; // Not supported
#elif defined(__MINGW32__)                        // Windows
    return 1; // Not supported
#else                                             // BSDs
    return wcwidth(wc);
#endif
}

inline __attribute__((always_inline)) int compat_wcswidth(int* s, __attribute__((unused)) size_t n) {
#if defined(__linux__)                            // Linux
    return wcswidth(s, n);
#elif defined(__APPLE__)                          // macOS
    return wcswidth(s, n);
#elif defined(__gnu_hurd__)                       // Hurd
    return (int) wcslen(w); // Not supported
#elif defined(__MINGW32__)                        // Windows
    return (int) wcslen(w); // Not supported
#else                                             // BSDs
    return wcswidth(s, n);
#endif
}
