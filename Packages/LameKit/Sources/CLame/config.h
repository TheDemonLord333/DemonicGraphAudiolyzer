/*
 * config.h for the vendored LAME 3.100 encoder library (libmp3lame).
 *
 * LAME normally generates this file with autoconf. This hand-written version
 * contains only the macros that libmp3lame 3.100 actually evaluates and is
 * valid for every platform this package is built for:
 *   - iOS devices (arm64), iOS Simulator (arm64 / x86_64), macOS,
 *   - Linux x86_64 / arm64 (used for local verification builds).
 *
 * Deliberately NOT defined:
 *   HAVE_XMMINTRIN_H  - SSE code paths are x86-only; iPhone is arm64.
 *   HAVE_NASM         - no assembler code.
 *   HAVE_MPGLIB       - the MP3 decoder is not needed (decoding is done by
 *                       AVFoundation); mpglib is not vendored.
 *   DECODE_ON_THE_FLY - depends on mpglib.
 *
 * All targets are little-endian IEEE-754 machines, therefore the
 * TAKEHIRO_IEEE754_HACK fast quantisation path is valid (same setting that
 * configure produces on these platforms).
 */
#ifndef LAME_CONFIG_H
#define LAME_CONFIG_H

#define STDC_HEADERS 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_LIMITS_H 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1

#define LAME_LIBRARY_BUILD 1
#define TAKEHIRO_IEEE754_HACK 1
#define USE_FAST_LOG 1

#define PACKAGE "lame"
#define PACKAGE_NAME "lame"
#define PACKAGE_VERSION "3.100"
#define VERSION "3.100"

#ifndef HAVE_IEEE754_FLOAT32_T
typedef float ieee754_float32_t;
#endif
#ifndef HAVE_IEEE754_FLOAT64_T
typedef double ieee754_float64_t;
#endif

#endif /* LAME_CONFIG_H */
