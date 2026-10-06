# MetalOffscreen: renders a triangle into an offscreen texture and reads it back with getBytes,
# checking the resulting pixels. Needs no window; prints PASS or FAIL.

configure_file(
	"${CMAKE_SOURCE_DIR}/src/external/metal/deps/indium/test/triangle/AAPLShaders.metallib"
	"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
	COPYONLY
)

add_devtest_app(MetalOffscreen
	SOURCES
		main.m
	LIBRARIES
		Metal
		Foundation
		objc
	RESOURCES
		"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
)

# <simd/simd.h> isn't part of Darling's SDK yet; use the minimal copy in src/simd.
# The triangle example's Renderer directory provides AAPLShaderTypes.h.
target_include_directories(MetalOffscreen PRIVATE "${CMAKE_SOURCE_DIR}/src/simd/include" "${CMAKE_SOURCE_DIR}/src/external/metal/examples/triangle/Renderer")
