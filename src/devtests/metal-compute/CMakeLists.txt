configure_file(
	"${CMAKE_SOURCE_DIR}/src/external/metal/deps/indium/test/basic-compute/add.metallib"
	"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
	COPYONLY
)

add_devtest_app(MetalCompute
	SOURCES
		main.m
	LIBRARIES
		Metal
		Foundation
		objc
	RESOURCES
		"${CMAKE_CURRENT_BINARY_DIR}/default.metallib"
)
