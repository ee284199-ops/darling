# OpenGLTexture: draws a textured quad through NSOpenGLContext the way glutin (Alacritty, Neovide)
# does: the context is made current before it gets its view, GL functions come from
# CFBundleGetFunctionPointerForName on com.apple.opengl, texture rows are uploaded with
# glTexSubImage2D and the quad is placed by float uniforms. Reads the pixels back and prints
# PASS or FAIL. Needs an X display with GL.
add_devtest_app(OpenGLTexture
	SOURCES
		main.m
	LIBRARIES
		AppKit
		OpenGL
		Foundation
		objc
)

# GLTrace: logs the OpenGL calls an app makes through functions it gets from
# CFBundleGetFunctionPointerForName (see gltrace.c). Use it with
#   DYLD_INSERT_LIBRARIES=<build>/src/devtests/opengl-texture/libGLTrace.dylib GLTRACE_FILE=<log>
# never installed: skip the dSYM install rule
set(GLTrace_NO_DSYM TRUE)
add_darling_library(GLTrace SHARED gltrace.c)
target_link_libraries(GLTrace PRIVATE system CoreFoundation OpenGL objc)
