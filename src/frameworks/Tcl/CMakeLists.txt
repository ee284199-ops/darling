project(Tcl)

# Tcl.framework, built from the upstream Tcl sources in src/external/tcl the way
# Tcl's own unix/macosx build makes it (with threads), configured by tclConfig.h.

include(InstallSymlink)

set(TCL_SOURCE_DIR "${CMAKE_SOURCE_DIR}/src/external/tcl")
set(TCL_VERSION "8.5")
set(TCL_FRAMEWORK_ROOT "/System/Library/Frameworks/Tcl.framework")
set(TCL_FRAMEWORK_DIR "${TCL_FRAMEWORK_ROOT}/Versions/${TCL_VERSION}")
set(TCL_SCRIPTS_DIR "${TCL_FRAMEWORK_DIR}/Resources/Scripts")

set(tcl_generic_sources
	regcomp.c regexec.c regfree.c regerror.c tclAlloc.c tclAsync.c tclBasic.c tclBinary.c
	tclCkalloc.c tclClock.c tclCmdAH.c tclCmdIL.c tclCmdMZ.c tclCompCmds.c tclCompExpr.c
	tclCompile.c tclConfig.c tclDate.c tclDictObj.c tclEncoding.c tclEnv.c tclEvent.c
	tclExecute.c tclFCmd.c tclFileName.c tclGet.c tclHash.c tclHistory.c tclIndexObj.c
	tclInterp.c tclIO.c tclIOCmd.c tclIORChan.c tclIOGT.c tclIOSock.c tclIOUtil.c tclLink.c
	tclListObj.c tclLiteral.c tclLoad.c tclMain.c tclNamesp.c tclNotify.c tclObj.c tclPanic.c
	tclParse.c tclPathObj.c tclPipe.c tclPkg.c tclPkgConfig.c tclPosixStr.c tclPreserve.c
	tclProc.c tclRegexp.c tclResolve.c tclResult.c tclScan.c tclStringObj.c tclStrToD.c
	tclThread.c tclThreadAlloc.c tclThreadJoin.c tclThreadStorage.c tclStubInit.c tclStubLib.c
	tclTimer.c tclTrace.c tclUtf.c tclUtil.c tclVar.c tclTomMathInterface.c
)

# the Unix sources, minus the notifier: on Mac OS X, tclMacOSXNotify.c replaces tclUnixNotfy.c
set(tcl_unix_sources
	tclUnixChan.c tclUnixEvent.c tclUnixFCmd.c tclUnixFile.c tclUnixPipe.c tclUnixSock.c
	tclUnixTime.c tclUnixInit.c tclUnixThrd.c tclUnixCompat.c tclLoadDyld.c
)

set(tcl_macosx_sources
	tclMacOSXBundle.c tclMacOSXFCmd.c tclMacOSXNotify.c
)

set(tcl_tommath_sources
	bncore.c bn_reverse.c bn_fast_s_mp_mul_digs.c bn_fast_s_mp_sqr.c bn_mp_add.c bn_mp_and.c
	bn_mp_add_d.c bn_mp_clamp.c bn_mp_clear.c bn_mp_clear_multi.c bn_mp_cmp.c bn_mp_cmp_d.c
	bn_mp_cmp_mag.c bn_mp_cnt_lsb.c bn_mp_copy.c bn_mp_count_bits.c bn_mp_div.c bn_mp_div_d.c
	bn_mp_div_2.c bn_mp_div_2d.c bn_mp_div_3.c bn_mp_exch.c bn_mp_expt_d.c bn_mp_grow.c
	bn_mp_init.c bn_mp_init_copy.c bn_mp_init_multi.c bn_mp_init_set.c bn_mp_init_set_int.c
	bn_mp_init_size.c bn_mp_karatsuba_mul.c bn_mp_karatsuba_sqr.c bn_mp_lshd.c bn_mp_mod.c
	bn_mp_mod_2d.c bn_mp_mul.c bn_mp_mul_2.c bn_mp_mul_2d.c bn_mp_mul_d.c bn_mp_neg.c bn_mp_or.c
	bn_mp_radix_size.c bn_mp_radix_smap.c bn_mp_read_radix.c bn_mp_rshd.c bn_mp_set.c
	bn_mp_set_int.c bn_mp_shrink.c bn_mp_sqr.c bn_mp_sqrt.c bn_mp_sub.c bn_mp_sub_d.c
	bn_mp_to_unsigned_bin.c bn_mp_to_unsigned_bin_n.c bn_mp_toom_mul.c bn_mp_toom_sqr.c
	bn_mp_toradix_n.c bn_mp_unsigned_bin_size.c bn_mp_xor.c bn_mp_zero.c bn_s_mp_add.c
	bn_s_mp_mul_digs.c bn_s_mp_sqr.c bn_s_mp_sub.c
)

set(tcl_sources)
foreach(source IN LISTS tcl_generic_sources)
	list(APPEND tcl_sources "${TCL_SOURCE_DIR}/generic/${source}")
endforeach()
foreach(source IN LISTS tcl_unix_sources)
	list(APPEND tcl_sources "${TCL_SOURCE_DIR}/unix/${source}")
endforeach()
foreach(source IN LISTS tcl_macosx_sources)
	list(APPEND tcl_sources "${TCL_SOURCE_DIR}/macosx/${source}")
endforeach()
foreach(source IN LISTS tcl_tommath_sources)
	list(APPEND tcl_sources "${TCL_SOURCE_DIR}/libtommath/${source}")
endforeach()

# like configure's DEFS: -DHAVE_TCL_CONFIG_H -imacros tclConfig.h
add_definitions(-DHAVE_TCL_CONFIG_H)
add_compile_options(-imacros "${CMAKE_CURRENT_SOURCE_DIR}/tclConfig.h" -w)

set_property(SOURCE "${TCL_SOURCE_DIR}/unix/tclUnixInit.c" APPEND PROPERTY COMPILE_DEFINITIONS
	"TCL_LIBRARY=\"${TCL_SCRIPTS_DIR}\""
	"TCL_PACKAGE_PATH=\"~/Library/Tcl /Library/Tcl /System/Library/Tcl ~/Library/Frameworks /Library/Frameworks /System/Library/Frameworks\""
)

set_property(SOURCE "${TCL_SOURCE_DIR}/generic/tclPkgConfig.c" APPEND PROPERTY COMPILE_DEFINITIONS
	"CFG_INSTALL_LIBDIR=\"${TCL_FRAMEWORK_DIR}\""
	"CFG_INSTALL_BINDIR=\"/usr/bin\""
	"CFG_INSTALL_SCRDIR=\"${TCL_SCRIPTS_DIR}\""
	"CFG_INSTALL_INCDIR=\"${TCL_FRAMEWORK_DIR}/Headers\""
	"CFG_INSTALL_DOCDIR=\"/usr/share/man\""
	"CFG_RUNTIME_LIBDIR=\"${TCL_FRAMEWORK_DIR}\""
	"CFG_RUNTIME_BINDIR=\"/usr/bin\""
	"CFG_RUNTIME_SCRDIR=\"${TCL_SCRIPTS_DIR}\""
	"CFG_RUNTIME_INCDIR=\"${TCL_FRAMEWORK_DIR}/Headers\""
	"CFG_RUNTIME_DOCDIR=\"/usr/share/man\""
)

# what macOS' Tcl 8.5 reports, so apps linked against it accept this one
set(DYLIB_COMPAT_VERSION "8.5.0")
set(DYLIB_CURRENT_VERSION "8.5.19")
add_framework(Tcl
	FAT
	CURRENT_VERSION
	VERSION "${TCL_VERSION}"
	SOURCES
		${tcl_sources}
	DEPENDENCIES
		system
		CoreFoundation
	RESOURCES
		Info.plist Info.plist
)
unset(DYLIB_COMPAT_VERSION)
unset(DYLIB_CURRENT_VERSION)

# in this order: generic/tommath.h has to win over libtommath's own, since it renames the
# bignum functions to TclBN_*, and the SDK's tcl.h must not be found instead of ours
target_include_directories(Tcl BEFORE PRIVATE
	"${CMAKE_CURRENT_SOURCE_DIR}"
	"${TCL_SOURCE_DIR}/generic"
	"${TCL_SOURCE_DIR}/unix"
	"${TCL_SOURCE_DIR}/libtommath"
)

install(FILES
	"${TCL_SOURCE_DIR}/generic/tcl.h"
	"${TCL_SOURCE_DIR}/generic/tclDecls.h"
	"${TCL_SOURCE_DIR}/generic/tclPlatDecls.h"
	"${TCL_SOURCE_DIR}/generic/tclTomMath.h"
	"${TCL_SOURCE_DIR}/generic/tclTomMathDecls.h"
	DESTINATION "libexec/darling${TCL_FRAMEWORK_DIR}/Headers"
)
InstallSymlink("Versions/Current/Headers" "${CMAKE_INSTALL_PREFIX}/libexec/darling${TCL_FRAMEWORK_ROOT}/Headers")

# the script library (init.tcl and friends) that Tcl_Init looks for in Resources/Scripts
install(DIRECTORY "${TCL_SOURCE_DIR}/library/"
	DESTINATION "libexec/darling${TCL_SCRIPTS_DIR}"
	PATTERN "dde" EXCLUDE
	PATTERN "reg" EXCLUDE
)

# tclsh, as /usr/bin/tclsh8.5 and /usr/bin/tclsh like on macOS
include(darling_exe)
add_darling_executable(tclsh "${TCL_SOURCE_DIR}/unix/tclAppInit.c")
target_include_directories(tclsh BEFORE PRIVATE
	"${CMAKE_CURRENT_SOURCE_DIR}"
	"${TCL_SOURCE_DIR}/generic"
	"${TCL_SOURCE_DIR}/unix"
)
target_link_libraries(tclsh system Tcl)
set_target_properties(tclsh PROPERTIES OUTPUT_NAME "tclsh${TCL_VERSION}")
make_fat(tclsh)
install(TARGETS tclsh DESTINATION libexec/darling/usr/bin)
InstallSymlink("tclsh${TCL_VERSION}" "${CMAKE_INSTALL_PREFIX}/libexec/darling/usr/bin/tclsh")
