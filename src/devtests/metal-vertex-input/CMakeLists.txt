# MetalVertexInput: draws a triangle whose vertex shader reads its position through [[stage_in]]
# with an MTLVertexDescriptor, offscreen, and checks the pixels. Needs no window; prints PASS or FAIL.

configure_file(
	"${CMAKE_SOURCE_DIR}/src/external/metal/deps/indium/test/cubemap/shaders.metallib"
	"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
	COPYONLY
)

add_devtest_app(MetalVertexInput
	SOURCES
		main.m
	LIBRARIES
		Metal
		Foundation
		objc
	RESOURCES
		"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
)
