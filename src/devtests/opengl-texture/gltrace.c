// GLTrace: a debugging aid for OpenGL apps under Darling. Inserted with
//   DYLD_INSERT_LIBRARIES=<path>/libGLTrace.dylib GLTRACE_FILE=<log path>
// it interposes CFBundleGetFunctionPointerForName (which glutin and many other loaders use to find
// OpenGL functions in com.apple.opengl) and hands out logging wrappers for the calls that decide
// what ends up on screen: texture uploads (with a checksum of the pixels), uniforms, blending,
// buffers and draws.

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static FILE* out;

static FILE* logFile(void)
{
	if (out == NULL) {
		const char* path = getenv("GLTRACE_FILE");
		out = path != NULL ? fopen(path, "w") : NULL;
		if (out == NULL)
			out = stderr;
		setvbuf(out, NULL, _IOLBF, 0);
	}
	return out;
}

static size_t bytesPerPixel(unsigned int format, unsigned int type)
{
	size_t components = format == 0x1907 /* RGB */ ? 3 : format == 0x1908 /* RGBA */ || format == 0x80E1 /* BGRA */ ? 4 : 1;
	return type == 0x1401 /* UNSIGNED_BYTE */ ? components : components * 4;
}

static void describePixels(const void* pixels, size_t length, char* buffer, size_t size)
{
	const uint8_t* bytes = pixels;
	unsigned long sum = 0, nonzero = 0;
	size_t i;

	if (pixels == NULL) {
		snprintf(buffer, size, "pixels=NULL");
		return;
	}
	for (i = 0; i < length; i++) {
		sum += bytes[i];
		if (bytes[i] != 0)
			nonzero++;
	}
	snprintf(buffer, size, "bytes=%zu nonzero=%lu sum=%lu", length, nonzero, sum);
}

// the CGL context that is current on this thread, to catch draws going to someone else's context
extern void* CGLGetCurrentContext(void);

// After every glDrawElements(Instanced) with GLTRACE_READBACK set: read back the top-left 240x48
// pixels of the default framebuffer and count the ones that differ from the top-left pixel.
static void readBack(const char* what)
{
	static void (*finish)(void);
	static void (*readPixels)(int, int, int, int, unsigned int, unsigned int, void*);
	static void (*getIntegerv)(unsigned int, int*);
	static int enabled = -1;
	uint8_t pixels[240 * 48 * 4];
	int viewport[4];
	size_t i, differing = 0;

	if (enabled < 0)
		enabled = getenv("GLTRACE_READBACK") != NULL;
	if (!enabled)
		return;
	if (finish == NULL) {
		CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
		finish = (void (*)(void)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glFinish"));
		readPixels = (void (*)(int, int, int, int, unsigned int, unsigned int, void*)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glReadPixels"));
		getIntegerv = (void (*)(unsigned int, int*)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glGetIntegerv"));
	}
	finish();
	getIntegerv(0x0BA2 /* GL_VIEWPORT */, viewport);
	readPixels(0, viewport[3] - 48, 240, 48, 0x1908, 0x1401, pixels);
	for (i = 0; i < 240 * 48; i++) {
		if (abs(pixels[i * 4] - pixels[(47 * 240) * 4]) > 8 || abs(pixels[i * 4 + 1] - pixels[(47 * 240) * 4 + 1]) > 8)
			differing++;
	}
	fprintf(logFile(), "  readback after %s: viewport %dx%d, top-left pixel %u %u %u, %zu of %d pixels differ\n",
		what, viewport[2], viewport[3], pixels[(47 * 240) * 4], pixels[(47 * 240) * 4 + 1], pixels[(47 * 240) * 4 + 2],
		differing, 240 * 48);
}

#define VOID_WRAPPER(name, params, args, format, ...) \
	static void (*real_##name) params; \
	static void wrap_##name params \
	{ \
		fprintf(logFile(), #name " " format "\n", __VA_ARGS__); \
		real_##name args; \
	}

VOID_WRAPPER(glViewport, (int x, int y, int w, int h), (x, y, w, h), "%d %d %d %d", x, y, w, h)
VOID_WRAPPER(glScissor, (int x, int y, int w, int h), (x, y, w, h), "%d %d %d %d", x, y, w, h)
VOID_WRAPPER(glEnable, (unsigned int cap), (cap), "0x%x", cap)
VOID_WRAPPER(glDisable, (unsigned int cap), (cap), "0x%x", cap)
VOID_WRAPPER(glBlendFunc, (unsigned int s, unsigned int d), (s, d), "0x%x 0x%x", s, d)
VOID_WRAPPER(glBlendFuncSeparate, (unsigned int a, unsigned int b, unsigned int c, unsigned int d), (a, b, c, d), "0x%x 0x%x 0x%x 0x%x", a, b, c, d)
VOID_WRAPPER(glClearColor, (float r, float g, float b, float a), (r, g, b, a), "%.3f %.3f %.3f %.3f", r, g, b, a)
VOID_WRAPPER(glClear, (unsigned int mask), (mask), "0x%x", mask)
VOID_WRAPPER(glUseProgram, (unsigned int program), (program), "%u", program)
VOID_WRAPPER(glActiveTexture, (unsigned int unit), (unit), "0x%x", unit)
VOID_WRAPPER(glBindTexture, (unsigned int target, unsigned int texture), (target, texture), "0x%x %u", target, texture)
VOID_WRAPPER(glBindBuffer, (unsigned int target, unsigned int buffer), (target, buffer), "0x%x %u", target, buffer)
VOID_WRAPPER(glBindVertexArray, (unsigned int array), (array), "%u", array)
VOID_WRAPPER(glBindFramebuffer, (unsigned int target, unsigned int fb), (target, fb), "0x%x %u", target, fb)
VOID_WRAPPER(glPixelStorei, (unsigned int name, int value), (name, value), "0x%x %d", name, value)
VOID_WRAPPER(glUniform1i, (int location, int v), (location, v), "%d %d", location, v)
VOID_WRAPPER(glUniform1f, (int location, float v), (location, v), "%d %.3f", location, v)
VOID_WRAPPER(glUniform2f, (int location, float a, float b), (location, a, b), "%d %.4f %.4f", location, a, b)
VOID_WRAPPER(glUniform4f, (int location, float a, float b, float c, float d), (location, a, b, c, d), "%d %.4f %.4f %.4f %.4f", location, a, b, c, d)
VOID_WRAPPER(glVertexAttribPointer, (unsigned int i, int size, unsigned int type, unsigned char norm, int stride, const void* p),
	(i, size, type, norm, stride, p), "%u size=%d type=0x%x norm=%d stride=%d offset=%p", i, size, type, norm, stride, p)
VOID_WRAPPER(glVertexAttribIPointer, (unsigned int i, int size, unsigned int type, int stride, const void* p),
	(i, size, type, stride, p), "%u size=%d type=0x%x stride=%d offset=%p", i, size, type, stride, p)
VOID_WRAPPER(glVertexAttribDivisor, (unsigned int i, unsigned int divisor), (i, divisor), "%u %u", i, divisor)
VOID_WRAPPER(glEnableVertexAttribArray, (unsigned int i), (i), "%u", i)
VOID_WRAPPER(glBindAttribLocation, (unsigned int program, unsigned int index, const char* name), (program, index, name), "%u %u %s", program, index, name)
VOID_WRAPPER(glColorMask, (unsigned char r, unsigned char g, unsigned char b, unsigned char a), (r, g, b, a), "%d %d %d %d", r, g, b, a)
VOID_WRAPPER(glBlendEquation, (unsigned int mode), (mode), "0x%x", mode)
VOID_WRAPPER(glDrawBuffer, (unsigned int buffer), (buffer), "0x%x", buffer)
VOID_WRAPPER(glDepthMask, (unsigned char flag), (flag), "%d", flag)
static void (*real_glDrawArrays)(unsigned int, int, int);
static void wrap_glDrawArrays(unsigned int mode, int first, int count)
{
	fprintf(logFile(), "glDrawArrays 0x%x %d %d (CGL context %p)\n", mode, first, count, CGLGetCurrentContext());
	real_glDrawArrays(mode, first, count);
}
static void (*real_glDrawElements)(unsigned int, int, unsigned int, const void*);
static void wrap_glDrawElements(unsigned int mode, int count, unsigned int type, const void* indices)
{
	fprintf(logFile(), "glDrawElements 0x%x %d 0x%x %p (CGL context %p)\n", mode, count, type, indices, CGLGetCurrentContext());
	real_glDrawElements(mode, count, type, indices);
	readBack("glDrawElements");
}

#include <objc/message.h>
#include <objc/runtime.h>

// GL state that can make draws vanish, and whose context the app thinks is current
static void dumpState(void)
{
	static unsigned char (*isEnabled)(unsigned int);
	static void (*getIntegerv)(unsigned int, int*);
	static void (*getBooleanv)(unsigned int, unsigned char*);
	int depthFunc = 0, program = 0, drawFramebuffer = 0, stencilFunc = 0, vao = 0;
	unsigned char colorMask[4] = { 9, 9, 9, 9 }, depthMask = 9;
	void* appContext = NULL;
	id current;

	if (isEnabled == NULL) {
		CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
		isEnabled = (unsigned char (*)(unsigned int)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glIsEnabled"));
		getIntegerv = (void (*)(unsigned int, int*)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glGetIntegerv"));
		getBooleanv = (void (*)(unsigned int, unsigned char*)) CFBundleGetFunctionPointerForName(bundle, CFSTR("glGetBooleanv"));
	}
	getIntegerv(0x0B74 /* GL_DEPTH_FUNC */, &depthFunc);
	getIntegerv(0x8B8D /* GL_CURRENT_PROGRAM */, &program);
	getIntegerv(0x8CA6 /* GL_DRAW_FRAMEBUFFER_BINDING */, &drawFramebuffer);
	getIntegerv(0x0B92 /* GL_STENCIL_FUNC */, &stencilFunc);
	getIntegerv(0x85B5 /* GL_VERTEX_ARRAY_BINDING */, &vao);
	getBooleanv(0x0C23 /* GL_COLOR_WRITEMASK */, colorMask);
	getBooleanv(0x0B72 /* GL_DEPTH_WRITEMASK */, &depthMask);

	current = ((id (*)(id, SEL)) objc_msgSend)((id) objc_getClass("NSOpenGLContext"), sel_registerName("currentContext"));
	if (current != nil)
		appContext = ((void* (*)(id, SEL)) objc_msgSend)(current, sel_registerName("CGLContextObj"));

	fprintf(logFile(), "  state: NSOpenGLContext.currentContext's CGL context %p; depth test %d func 0x%x mask %d; stencil test %d func 0x%x; "
		"scissor %d; cull %d; blend %d; rasterizer discard %d; color mask %d%d%d%d; program %d; vao %d; draw framebuffer %d\n",
		appContext, isEnabled(0x0B71), depthFunc, depthMask, isEnabled(0x0B90), stencilFunc, isEnabled(0x0C11),
		isEnabled(0x0B44), isEnabled(0x0BE2), isEnabled(0x8C89), colorMask[0], colorMask[1], colorMask[2], colorMask[3],
		program, vao, drawFramebuffer);
}

static void (*real_glDrawElementsInstanced)(unsigned int, int, unsigned int, const void*, int);
static void wrap_glDrawElementsInstanced(unsigned int mode, int count, unsigned int type, const void* indices, int instances)
{
	fprintf(logFile(), "glDrawElementsInstanced 0x%x %d 0x%x %p instances=%d (CGL context %p)\n", mode, count, type, indices, instances, CGLGetCurrentContext());
	if (getenv("GLTRACE_READBACK") != NULL)
		dumpState();
	real_glDrawElementsInstanced(mode, count, type, indices, instances);
	readBack("glDrawElementsInstanced");
}

static void (*real_glTexImage2D)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*);
static void wrap_glTexImage2D(unsigned int target, int level, int internal, int w, int h, int border,
                              unsigned int format, unsigned int type, const void* pixels)
{
	char info[128];
	describePixels(pixels, (size_t) w * h * bytesPerPixel(format, type), info, sizeof(info));
	fprintf(logFile(), "glTexImage2D 0x%x level=%d internal=0x%x %dx%d format=0x%x type=0x%x %s\n",
		target, level, internal, w, h, format, type, info);
	real_glTexImage2D(target, level, internal, w, h, border, format, type, pixels);
}

static void (*real_glTexSubImage2D)(unsigned int, int, int, int, int, int, unsigned int, unsigned int, const void*);
static void wrap_glTexSubImage2D(unsigned int target, int level, int x, int y, int w, int h,
                                 unsigned int format, unsigned int type, const void* pixels)
{
	char info[128];
	describePixels(pixels, (size_t) w * h * bytesPerPixel(format, type), info, sizeof(info));
	fprintf(logFile(), "glTexSubImage2D 0x%x level=%d at %d,%d %dx%d format=0x%x type=0x%x %s\n",
		target, level, x, y, w, h, format, type, info);
	real_glTexSubImage2D(target, level, x, y, w, h, format, type, pixels);
}

static void (*real_glBufferData)(unsigned int, long, const void*, unsigned int);
static void wrap_glBufferData(unsigned int target, long size, const void* data, unsigned int usage)
{
	fprintf(logFile(), "glBufferData 0x%x size=%ld data=%p usage=0x%x\n", target, size, data, usage);
	real_glBufferData(target, size, data, usage);
}

static void (*real_glBufferSubData)(unsigned int, long, long, const void*);
static void wrap_glBufferSubData(unsigned int target, long offset, long size, const void* data)
{
	char hex[3 * 48 + 1] = "";
	const uint8_t* bytes = data;
	long i;
	for (i = 0; data != NULL && i < size && i < 48; i++)
		snprintf(hex + i * 3, 4, "%02x ", bytes[i]);
	fprintf(logFile(), "glBufferSubData 0x%x offset=%ld size=%ld first bytes: %s\n", target, offset, size, hex);
	real_glBufferSubData(target, offset, size, data);
}

static int (*real_glGetUniformLocation)(unsigned int, const char*);
static int wrap_glGetUniformLocation(unsigned int program, const char* name)
{
	int location = real_glGetUniformLocation(program, name);
	fprintf(logFile(), "glGetUniformLocation %u %s -> %d\n", program, name, location);
	return location;
}

static void (*real_glLinkProgram)(unsigned int);
static void wrap_glLinkProgram(unsigned int program)
{
	fprintf(logFile(), "glLinkProgram %u\n", program);
	real_glLinkProgram(program);
}

static void (*real_glShaderSource)(unsigned int, int, const char* const*, const int*);
static void wrap_glShaderSource(unsigned int shader, int count, const char* const* strings, const int* lengths)
{
	int i;
	fprintf(logFile(), "glShaderSource %u count=%d\n", shader, count);
	for (i = 0; i < count; i++) {
		if (lengths != NULL && lengths[i] >= 0)
			fprintf(logFile(), "%.*s\n", lengths[i], strings[i]);
		else
			fprintf(logFile(), "%s\n", strings[i]);
	}
	real_glShaderSource(shader, count, strings, lengths);
}

static unsigned int (*real_glGetError)(void);
static unsigned int wrap_glGetError(void)
{
	unsigned int error = real_glGetError();
	if (error != 0)
		fprintf(logFile(), "glGetError -> 0x%x\n", error);
	return error;
}

#define ENTRY(name) { #name, (void**) &real_##name, (void*) wrap_##name }

static const struct {
	const char* name;
	void** real;
	void* wrapper;
} wrapped[] = {
	ENTRY(glViewport), ENTRY(glScissor), ENTRY(glEnable), ENTRY(glDisable), ENTRY(glBlendFunc),
	ENTRY(glBlendFuncSeparate), ENTRY(glClearColor), ENTRY(glClear), ENTRY(glUseProgram),
	ENTRY(glActiveTexture), ENTRY(glBindTexture), ENTRY(glBindBuffer), ENTRY(glBindVertexArray),
	ENTRY(glBindFramebuffer), ENTRY(glPixelStorei), ENTRY(glUniform1i), ENTRY(glUniform1f),
	ENTRY(glUniform2f), ENTRY(glUniform4f), ENTRY(glVertexAttribPointer), ENTRY(glVertexAttribIPointer),
	ENTRY(glVertexAttribDivisor), ENTRY(glEnableVertexAttribArray), ENTRY(glDrawArrays),
	ENTRY(glDrawElements), ENTRY(glDrawElementsInstanced), ENTRY(glTexImage2D), ENTRY(glTexSubImage2D),
	ENTRY(glBufferData), ENTRY(glBufferSubData), ENTRY(glGetUniformLocation), ENTRY(glLinkProgram),
	ENTRY(glShaderSource), ENTRY(glGetError), ENTRY(glBindAttribLocation), ENTRY(glColorMask),
	ENTRY(glBlendEquation), ENTRY(glDrawBuffer), ENTRY(glDepthMask),
};

static void* tracedGetFunctionPointerForName(CFBundleRef bundle, CFStringRef name)
{
	void* function = CFBundleGetFunctionPointerForName(bundle, name);
	char buffer[128];
	size_t i;

	if (function == NULL || !CFStringGetCString(name, buffer, sizeof(buffer), kCFStringEncodingUTF8))
		return function;

	for (i = 0; i < sizeof(wrapped) / sizeof(wrapped[0]); i++) {
		if (strcmp(buffer, wrapped[i].name) == 0) {
			*wrapped[i].real = function;
			return wrapped[i].wrapper;
		}
	}
	return function;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct {
	const void* replacement;
	const void* replacee;
} interposers[] = {
	{ (const void*) tracedGetFunctionPointerForName, (const void*) CFBundleGetFunctionPointerForName },
};
