#import "MetalTestApp.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

@interface MetalTestAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation MetalTestAppDelegate

- (void)applicationDidFinishLaunching: (NSNotification*)notification
{
	const char* autoquit = getenv("DEVTEST_AUTOQUIT");
	if (autoquit != NULL && atof(autoquit) > 0) {
		[NSTimer scheduledTimerWithTimeInterval: atof(autoquit) target: NSApp selector: @selector(terminate:) userInfo: nil repeats: NO];
	}
}

- (void)windowWillClose: (NSNotification*)notification
{
	[NSApp terminate: self];
}

@end

int MetalTestAppRun(NSString* title, void (^setUp)(MTKView* view))
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

		MetalTestAppDelegate* delegate = [MetalTestAppDelegate new];
		[NSApp setDelegate: delegate];

		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device) {
			fprintf(stderr, "no Metal device\n");
			return 1;
		}

		NSRect frame = NSMakeRect(0, 0, 800, 600);
		NSWindow* window = [[NSWindow alloc] initWithContentRect: frame
		                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
		                                                 backing: NSBackingStoreBuffered
		                                                   defer: NO];
		[window setTitle: title];
		[window setDelegate: delegate];

		MTKView* view = [[MTKView alloc] initWithFrame: frame device: device];
		setUp(view);
		[window setContentView: view];

		[window center];
		[window makeKeyAndOrderFront: nil];

		[NSApp run];
	}
	return 0;
}

void MetalTestMatrixIdentity(float m[16])
{
	memset(m, 0, 16 * sizeof(float));
	m[0] = m[5] = m[10] = m[15] = 1;
}

void MetalTestMatrixMultiply(float out[16], const float a[16], const float b[16])
{
	float result[16];
	for (int column = 0; column < 4; ++column) {
		for (int row = 0; row < 4; ++row) {
			float sum = 0;
			for (int k = 0; k < 4; ++k) {
				sum += a[k * 4 + row] * b[column * 4 + k];
			}
			result[column * 4 + row] = sum;
		}
	}
	memcpy(out, result, sizeof(result));
}

void MetalTestMatrixPerspective(float m[16], float fovyRadians, float aspect, float nearZ, float farZ)
{
	// right-handed view space looking down -Z, mapped to Metal's 0...1 depth range
	float ys = 1 / tanf(fovyRadians * 0.5f);
	float xs = ys / aspect;
	float zs = farZ / (nearZ - farZ);

	memset(m, 0, 16 * sizeof(float));
	m[0] = xs;
	m[5] = ys;
	m[10] = zs;
	m[11] = -1;
	m[14] = zs * nearZ;
}

void MetalTestMatrixRotation(float m[16], float radians, float x, float y, float z)
{
	float length = sqrtf(x * x + y * y + z * z);
	x /= length;
	y /= length;
	z /= length;

	float c = cosf(radians);
	float s = sinf(radians);
	float t = 1 - c;

	MetalTestMatrixIdentity(m);
	m[0] = t * x * x + c;
	m[1] = t * x * y + s * z;
	m[2] = t * x * z - s * y;
	m[4] = t * x * y - s * z;
	m[5] = t * y * y + c;
	m[6] = t * y * z + s * x;
	m[8] = t * x * z + s * y;
	m[9] = t * y * z - s * x;
	m[10] = t * z * z + c;
}

void MetalTestMatrixTranslation(float m[16], float x, float y, float z)
{
	MetalTestMatrixIdentity(m);
	m[12] = x;
	m[13] = y;
	m[14] = z;
}
