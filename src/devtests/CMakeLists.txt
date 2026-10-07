# Developer GUI test apps for Darling.
#
# Not built or installed by default: configure with -DDARLING_DEV_TESTS=ON, then
# run the bundles straight from the build tree inside Darling, e.g.
#   darling shell /Volumes/SystemRoot/<build>/src/devtests/appkit-basic/AppKitBasic.app/Contents/MacOS/AppKitBasic
project(devtests)

# add_devtest_app(<name> SOURCES <file>... [LIBRARIES <lib>...] [RESOURCES <file>...])
#
# Builds <name> as a Mach-O executable and assembles <name>.app in the current
# binary directory, copying RESOURCES into Contents/Resources.
function(add_devtest_app name)
	cmake_parse_arguments(APP "" "" "SOURCES;LIBRARIES;RESOURCES" ${ARGN})

	# test apps are never installed, so skip the dSYM install rules
	set(${name}_NO_DSYM TRUE)
	add_darling_executable(${name} ${APP_SOURCES} "${devtests_SOURCE_DIR}/common/UncaughtExceptionLogger.m")
	target_link_libraries(${name} ${APP_LIBRARIES} Foundation)

	set(contents "${CMAKE_CURRENT_BINARY_DIR}/${name}.app/Contents")
	set(DEVTEST_APP_NAME "${name}")
	configure_file("${devtests_SOURCE_DIR}/Info.plist.in" "${contents}/Info.plist" @ONLY)

	add_custom_command(TARGET ${name} POST_BUILD
		COMMAND "${CMAKE_COMMAND}" -E make_directory "${contents}/MacOS" "${contents}/Resources"
		COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:${name}>" "${contents}/MacOS/${name}"
	)
	if (APP_RESOURCES)
		add_custom_command(TARGET ${name} POST_BUILD
			COMMAND "${CMAKE_COMMAND}" -E copy ${APP_RESOURCES} "${contents}/Resources/"
		)
	endif()
endfunction()

add_subdirectory(appkit-basic)
add_subdirectory(appkit-text)
add_subdirectory(coreaudio-basics)
add_subdirectory(coregraphics-drawing)
add_subdirectory(coretext-fonts)
add_subdirectory(foundation-collections)
add_subdirectory(opengl-texture)
add_subdirectory(uti-types)

if (BUILD_METAL)
	add_subdirectory(metal-compute)
	add_subdirectory(metal-cube)
	add_subdirectory(metal-offscreen)
	add_subdirectory(metal-texture)
	add_subdirectory(metal-triangle)
	add_subdirectory(metal-vertex-input)
endif()
