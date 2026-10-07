// OpenGLTexture: draws through NSOpenGLContext the way glutin (Alacritty, Neovide) does, and checks
// the results with glReadPixels:
//  - the context is made current before it is given its view,
//  - GL functions come from CFBundleGetFunctionPointerForName on the com.apple.opengl bundle, and
//    the first call through such a pointer must get its floating point arguments (Darling's
//    wrappers used to lose them),
//  - a 3x3 RGB glyph-like image is uploaded into a bigger RGBA texture with glTexSubImage2D and
//    GL_UNPACK_ALIGNMENT 1 (rows of 9 bytes) and drawn on a quad placed by float uniforms,
//  - the same glyph is drawn with dual-source blending, as Alacritty draws text.
// Prints PASS or FAIL and exits non-zero on failure. Needs an X display with OpenGL.

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GL_NO_ERROR 0
#define GL_TRIANGLE_STRIP 0x0005
#define GL_TEXTURE_2D 0x0DE1
#define GL_COLOR_CLEAR_VALUE 0x0C22
#define GL_UNPACK_ALIGNMENT 0x0CF5
#define GL_PACK_ALIGNMENT 0x0D05
#define GL_BLEND 0x0BE2
#define GL_UNSIGNED_BYTE 0x1401
#define GL_FLOAT 0x1406
#define GL_RGB 0x1907
#define GL_RGBA 0x1908
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_NEAREST 0x2600
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_TEXTURE0 0x84C0
#define GL_SRC1_COLOR 0x88F9
#define GL_ONE_MINUS_SRC1_COLOR 0x88FA
#define GL_ARRAY_BUFFER 0x8892
#define GL_STATIC_DRAW 0x88E4
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_VERTEX_SHADER 0x8B31
#define GL_COMPILE_STATUS 0x8B81
#define GL_LINK_STATUS 0x8B82
#define GL_FRAMEBUFFER_COMPLETE 0x8CD5
#define GL_FRAMEBUFFER 0x8D40

#define GL_FUNCTIONS(X) \
	X(const unsigned char*, glGetString, (unsigned int name)) \
	X(unsigned int, glGetError, (void)) \
	X(unsigned int, glCheckFramebufferStatus, (unsigned int target)) \
	X(void, glGetFloatv, (unsigned int name, float* values)) \
	X(void, glViewport, (int x, int y, int width, int height)) \
	X(void, glClearColor, (float r, float g, float b, float a)) \
	X(void, glClear, (unsigned int mask)) \
	X(void, glEnable, (unsigned int cap)) \
	X(void, glDisable, (unsigned int cap)) \
	X(void, glBlendFunc, (unsigned int source, unsigned int destination)) \
	X(void, glPixelStorei, (unsigned int name, int value)) \
	X(void, glGenTextures, (int n, unsigned int* textures)) \
	X(void, glBindTexture, (unsigned int target, unsigned int texture)) \
	X(void, glActiveTexture, (unsigned int unit)) \
	X(void, glTexParameteri, (unsigned int target, unsigned int name, int value)) \
	X(void, glTexImage2D, (unsigned int target, int level, int internalFormat, int width, int height, int border, unsigned int format, unsigned int type, const void* pixels)) \
	X(void, glTexSubImage2D, (unsigned int target, int level, int x, int y, int width, int height, unsigned int format, unsigned int type, const void* pixels)) \
	X(unsigned int, glCreateShader, (unsigned int type)) \
	X(void, glShaderSource, (unsigned int shader, int count, const char* const* strings, const int* lengths)) \
	X(void, glCompileShader, (unsigned int shader)) \
	X(void, glGetShaderiv, (unsigned int shader, unsigned int name, int* value)) \
	X(void, glGetShaderInfoLog, (unsigned int shader, int size, int* length, char* log)) \
	X(unsigned int, glCreateProgram, (void)) \
	X(void, glAttachShader, (unsigned int program, unsigned int shader)) \
	X(void, glLinkProgram, (unsigned int program)) \
	X(void, glGetProgramiv, (unsigned int program, unsigned int name, int* value)) \
	X(void, glGetProgramInfoLog, (unsigned int program, int size, int* length, char* log)) \
	X(void, glUseProgram, (unsigned int program)) \
	X(int, glGetUniformLocation, (unsigned int program, const char* name)) \
	X(void, glGetUniformfv, (unsigned int program, int location, float* values)) \
	X(void, glUniform1i, (int location, int value)) \
	X(void, glUniform2f, (int location, float x, float y)) \
	X(void, glUniform4f, (int location, float x, float y, float z, float w)) \
	X(void, glGenVertexArrays, (int n, unsigned int* arrays)) \
	X(void, glBindVertexArray, (unsigned int array)) \
	X(void, glGenBuffers, (int n, unsigned int* buffers)) \
	X(void, glBindBuffer, (unsigned int target, unsigned int buffer)) \
	X(void, glBufferData, (unsigned int target, long size, const void* data, unsigned int usage)) \
	X(void, glEnableVertexAttribArray, (unsigned int index)) \
	X(void, glVertexAttribPointer, (unsigned int index, int size, unsigned int type, unsigned char normalized, int stride, const void* pointer)) \
	X(void, glDrawArrays, (unsigned int mode, int first, int count)) \
	X(void, glFinish, (void)) \
	X(void, glReadPixels, (int x, int y, int width, int height, unsigned int format, unsigned int type, void* pixels))

// prefixed: AppKit's headers already declare the GL functions themselves
#define DECLARE(ret, name, args) static ret (*fn_##name) args;
GL_FUNCTIONS(DECLARE)

static int failures = 0;

static void fail(const char* what)
{
	fprintf(stderr, "FAIL: %s\n", what);
	++failures;
}

static BOOL loadFunctions(void)
{
	// how glutin finds OpenGL functions on macOS
	CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
	if (bundle == NULL) {
		fail("CFBundleGetBundleWithIdentifier(com.apple.opengl) returned NULL");
		return NO;
	}

#define LOAD(ret, fn, args) \
	fn_##fn = (ret (*) args) CFBundleGetFunctionPointerForName(bundle, CFSTR(#fn)); \
	if (fn_##fn == NULL) { \
		fail("CFBundleGetFunctionPointerForName(" #fn ") returned NULL"); \
		return NO; \
	}
	GL_FUNCTIONS(LOAD)
	return YES;
}

static unsigned int compile(unsigned int type, const char* source)
{
	unsigned int shader = fn_glCreateShader(type);
	int ok = 0;

	fn_glShaderSource(shader, 1, &source, NULL);
	fn_glCompileShader(shader);
	fn_glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[1024] = "";
		fn_glGetShaderInfoLog(shader, sizeof(log), NULL, log);
		fprintf(stderr, "shader log: %s\n", log);
		fail("a shader didn't compile");
	}
	return shader;
}

static unsigned int linkProgram(const char* vertexSource, const char* fragmentSource)
{
	unsigned int program = fn_glCreateProgram();
	int linked = 0;

	fn_glAttachShader(program, compile(GL_VERTEX_SHADER, vertexSource));
	fn_glAttachShader(program, compile(GL_FRAGMENT_SHADER, fragmentSource));
	fn_glLinkProgram(program);
	fn_glGetProgramiv(program, GL_LINK_STATUS, &linked);
	if (!linked) {
		char log[1024] = "";
		fn_glGetProgramInfoLog(program, sizeof(log), NULL, log);
		fprintf(stderr, "program log: %s\n", log);
		fail("a program didn't link");
	}
	return program;
}

static const char* vertexSource =
	"#version 330 core\n"
	"layout(location = 0) in vec2 corner;\n"
	"uniform vec2 offset;\n"
	"uniform vec2 scale;\n"
	"out vec2 cornerUV;\n"
	"void main() {\n"
	"    cornerUV = corner;\n"
	"    gl_Position = vec4(offset + corner * scale, 0.0, 1.0);\n"
	"}\n";

static const char* fragmentSource =
	"#version 330 core\n"
	"in vec2 cornerUV;\n"
	"uniform sampler2D mask;\n"
	"uniform vec4 uvRect; // origin, size in the atlas\n"
	"uniform vec4 tint;\n"
	"out vec4 color;\n"
	"void main() {\n"
	"    vec3 m = texture(mask, uvRect.xy + cornerUV * uvRect.zw).rgb;\n"
	"    color = vec4(tint.rgb * m, 1.0);\n"
	"}\n";

// like Alacritty's text shader: the glyph is a per-channel coverage mask for the blend
static const char* dualSourceFragmentSource =
	"#version 330 core\n"
	"in vec2 cornerUV;\n"
	"uniform sampler2D mask;\n"
	"uniform vec4 uvRect;\n"
	"uniform vec4 tint;\n"
	"layout(location = 0, index = 0) out vec4 color;\n"
	"layout(location = 0, index = 1) out vec4 alphaMask;\n"
	"void main() {\n"
	"    vec3 m = texture(mask, uvRect.xy + cornerUV * uvRect.zw).rgb;\n"
	"    alphaMask = vec4(m, m.r);\n"
	"    color = vec4(tint.rgb, 1.0);\n"
	"}\n";

static void checkPixel(int x, int y, int r, int g, int b, const char* what)
{
	uint8_t p[4];

	fn_glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p);
	printf("%s: pixel (%d,%d) = R:%u G:%u B:%u\n", what, x, y, p[0], p[1], p[2]);
	if (abs(p[0] - r) > 3 || abs(p[1] - g) > 3 || abs(p[2] - b) > 3) {
		fprintf(stderr, "FAIL: %s is R:%u G:%u B:%u, expected R:%d G:%d B:%d\n", what, p[0], p[1], p[2], r, g, b);
		++failures;
	}
}

static void drawGlyph(unsigned int program)
{
	fn_glUseProgram(program);
	fn_glUniform1i(fn_glGetUniformLocation(program, "mask"), 0);
	// the quad covers the middle of the view: NDC -0.5 .. 0.5
	fn_glUniform2f(fn_glGetUniformLocation(program, "offset"), -0.5f, -0.5f);
	fn_glUniform2f(fn_glGetUniformLocation(program, "scale"), 1.0f, 1.0f);
	// sample the middle texel of the glyph
	fn_glUniform4f(fn_glGetUniformLocation(program, "uvRect"), 6.0f / 64, 6.0f / 64, 0.5f / 64, 0.5f / 64);
	fn_glUniform4f(fn_glGetUniformLocation(program, "tint"), 0.0f, 1.0f, 0.0f, 1.0f);
	fn_glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
	fn_glFinish();
}

static int run(void)
{
	const int size = 128;
	NSWindow* window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, size, size)
	                                               styleMask: NSWindowStyleMaskTitled
	                                                 backing: NSBackingStoreBuffered
	                                                   defer: NO];
	[window setTitle: @"OpenGLTexture"];
	NSView* view = [window contentView];
	[window makeKeyAndOrderFront: nil];

	NSOpenGLPixelFormatAttribute attributes[] = {
		NSOpenGLPFADoubleBuffer,
		NSOpenGLPFAColorSize, 24,
		0
	};
	NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes: attributes];
	NSOpenGLContext* context = [[NSOpenGLContext alloc] initWithFormat: format shareContext: nil];

	// glutin's order: current first, the view afterwards
	[context makeCurrentContext];
	[context setView: view];

	if (!loadFunctions())
		return 1;

	printf("GL_VERSION: %s\nGL_RENDERER: %s\n", fn_glGetString(GL_VERSION), fn_glGetString(GL_RENDERER));

	if (fn_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
		fail("the default framebuffer is incomplete after setView:");

	// 1. the very first call through a function pointer must get its floating point arguments
	float clear[4] = { -1, -1, -1, -1 };
	fn_glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
	fn_glGetFloatv(GL_COLOR_CLEAR_VALUE, clear);
	printf("first glClearColor(0.25, 0.5, 0.75, 1) set %.3f %.3f %.3f %.3f\n", clear[0], clear[1], clear[2], clear[3]);
	if (fabsf(clear[0] - 0.25f) > 0.001f || fabsf(clear[1] - 0.5f) > 0.001f || fabsf(clear[2] - 0.75f) > 0.001f)
		fail("the first glClearColor call lost its arguments");

	// 2. a glyph-like texture and a quad placed by uniforms
	unsigned int texture;
	uint8_t glyph[3 * 3 * 3];
	memset(glyph, 255, sizeof(glyph));

	fn_glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	fn_glGenTextures(1, &texture);
	fn_glActiveTexture(GL_TEXTURE0);
	fn_glBindTexture(GL_TEXTURE_2D, texture);
	fn_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	fn_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	fn_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	fn_glTexSubImage2D(GL_TEXTURE_2D, 0, 5, 5, 3, 3, GL_RGB, GL_UNSIGNED_BYTE, glyph);

	unsigned int program = linkProgram(vertexSource, fragmentSource);
	unsigned int dualSourceProgram = linkProgram(vertexSource, dualSourceFragmentSource);
	if (failures > 0)
		return 1;

	// the first glUniform2f call of the run (Alacritty sets its cell size with it), read back
	float pair[2] = { -1, -1 };
	int offsetLocation = fn_glGetUniformLocation(program, "offset");
	fn_glUseProgram(program);
	fn_glUniform2f(offsetLocation, 0.25f, 0.75f);
	fn_glGetUniformfv(program, offsetLocation, pair);
	printf("first glUniform2f(0.25, 0.75) set %.3f %.3f\n", pair[0], pair[1]);
	if (fabsf(pair[0] - 0.25f) > 0.001f || fabsf(pair[1] - 0.75f) > 0.001f)
		fail("the first glUniform2f call lost its arguments");

	const float corners[] = { 0, 0, 1, 0, 0, 1, 1, 1 };
	unsigned int vao, vbo;
	fn_glGenVertexArrays(1, &vao);
	fn_glBindVertexArray(vao);
	fn_glGenBuffers(1, &vbo);
	fn_glBindBuffer(GL_ARRAY_BUFFER, vbo);
	fn_glBufferData(GL_ARRAY_BUFFER, sizeof(corners), corners, GL_STATIC_DRAW);
	fn_glEnableVertexAttribArray(0);
	fn_glVertexAttribPointer(0, 2, GL_FLOAT, 0, 0, NULL);

	fn_glViewport(0, 0, size, size);
	fn_glPixelStorei(GL_PACK_ALIGNMENT, 1);
	fn_glClearColor(0.1f, 0.1f, 0.1f, 1.0f);
	fn_glClear(GL_COLOR_BUFFER_BIT);
	drawGlyph(program);

	// glReadPixels rows start at the bottom
	checkPixel(size / 2, size / 2, 0, 255, 0, "textured quad: inside");
	checkPixel(4, 4, 26, 26, 26, "textured quad: outside");

	// 3. dual-source blending: color * mask + destination * (1 - mask)
	fn_glClear(GL_COLOR_BUFFER_BIT);
	fn_glEnable(GL_BLEND);
	fn_glBlendFunc(GL_SRC1_COLOR, GL_ONE_MINUS_SRC1_COLOR);
	drawGlyph(dualSourceProgram);
	fn_glDisable(GL_BLEND);
	checkPixel(size / 2, size / 2, 0, 255, 0, "dual-source blended glyph: inside");
	checkPixel(4, 4, 26, 26, 26, "dual-source blended glyph: outside");

	unsigned int error = fn_glGetError();
	if (error != GL_NO_ERROR) {
		fprintf(stderr, "glGetError: 0x%x\n", error);
		fail("GL reported an error");
	}

	[context flushBuffer];

	if (failures > 0) {
		fprintf(stderr, "%d checks failed\n", failures);
		return 1;
	}
	printf("PASS: OpenGL through NSOpenGLContext and CFBundle function pointers\n");
	return 0;
}

int main(int argc, const char** argv)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp finishLaunching];
		return run();
	}
}
