/*
 * What Tcl's unix/configure (--enable-threads) finds on 64-bit macOS, for building
 * Darling's Tcl.framework without running configure. Like configure's build, every
 * source file gets this with -imacros (and HAVE_TCL_CONFIG_H makes tclPort.h include it).
 */

#ifndef _DARLING_TCL_CONFIG_H
#define _DARLING_TCL_CONFIG_H

/* headers */
#define STDC_HEADERS 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_MEMORY_H 1
#define HAVE_STRINGS_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_UNISTD_H 1
#define HAVE_LIMITS_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_TIME_H 1
#define TIME_WITH_SYS_TIME 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_FILIO_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_AVAILABILITYMACROS_H 1
#define HAVE_COPYFILE_H 1
#define HAVE_LIBKERN_OSATOMIC_H 1
#define NO_VALUES_H 1
#define USE_TERMIOS 1

/* types */
#define HAVE_INTPTR_T 1
#define HAVE_UINTPTR_T 1
#define HAVE_SIGNED_CHAR 1
#define HAVE_BLKCNT_T 1
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_STRUCT_STAT_ST_BLOCKS 1
#define HAVE_CAST_TO_UNION 1
#define NO_UNION_WAIT 1

/* functions */
#define HAVE_MKTIME 1
#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1
#define HAVE_TM_GMTOFF 1
#define HAVE_GETPWUID_R 1
#define HAVE_GETPWUID_R_5 1
#define HAVE_GETPWNAM_R 1
#define HAVE_GETPWNAM_R_5 1
#define HAVE_GETGRGID_R 1
#define HAVE_GETGRGID_R_5 1
#define HAVE_GETGRNAM_R 1
#define HAVE_GETGRNAM_R_5 1
#define HAVE_GETADDRINFO 1
#define HAVE_MTSAFE_GETHOSTBYNAME 1
#define HAVE_MTSAFE_GETHOSTBYADDR 1
#define HAVE_CHFLAGS 1
#define HAVE_LANGINFO 1
#define HAVE_FTS 1
#define HAVE_GETATTRLIST 1
#define HAVE_COPYFILE 1
#define HAVE_OSSPINLOCKLOCK 1
#define HAVE_WEAK_IMPORT 1

/* threads */
#define TCL_THREADS 1
#define USE_THREAD_ALLOC 1
#define _REENTRANT 1
#define _THREAD_SAFE 1
#define HAVE_PTHREAD_ATTR_SETSTACKSIZE 1
#define HAVE_PTHREAD_ATFORK 1
#define HAVE_PTHREAD_GET_STACKSIZE_NP 1

/* libtommath */
#define TCL_TOMMATH 1
#define MP_PREC 4

/* Darwin */
#define MAC_OSX_TCL 1
#define HAVE_COREFOUNDATION 1
#define _DARWIN_C_SOURCE 1
#define TCL_DEFAULT_ENCODING "utf-8"
#define TCL_WIDE_CLICKS 1
#define TCL_SHLIB_EXT ".dylib"
#define TCL_FRAMEWORK_VERSION "8.5"
#define MODULE_SCOPE extern __attribute__((__visibility__("hidden")))

/* build configuration, reported by [::tcl::pkgconfig] */
#define TCL_CFGVAL_ENCODING "utf-8"
#define TCL_CFG_OPTIMIZED 1
#define TCL_CFG_DO64BIT 1

#endif /* _DARLING_TCL_CONFIG_H */
