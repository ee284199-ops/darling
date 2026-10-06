# The darling-metal "triangle" example, built as an app bundle.
#
# The example's own build.sh needs Apple's `metal` compiler for the shader.
# Indium ships the same shader precompiled (the sources differ only in their
# license header), so that file becomes the bundle's default.metallib.
set(example_dir "${CMAKE_SOURCE_DIR}/src/external/metal/examples/triangle")

configure_file(
	"${CMAKE_SOURCE_DIR}/src/external/metal/deps/indium/test/triangle/AAPLShaders.metallib"
	"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
	COPYONLY
)

add_devtest_app(MetalTriangle
	SOURCES
		"${example_dir}/main.m"
		"${example_dir}/Renderer/AAPLRenderer.m"
	LIBRARIES
		AppKit
		Metal
		MetalKit
		QuartzCore
		Foundation
		objc
	RESOURCES
		"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
)

# <simd/simd.h> isn't part of Darling's SDK yet; use the minimal copy in src/simd.
target_include_directories(MetalTriangle PRIVATE "${CMAKE_SOURCE_DIR}/src/simd/include")
