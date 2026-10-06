// Shared scaffolding for the windowed Metal test apps.

#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>

// Opens a window titled `title` whose content is an 800x600 MTKView on the default device, lets
// `setUp` configure the view (it must set a delegate and keep that delegate alive), then runs the
// app until the window is closed, or for DEVTEST_AUTOQUIT seconds when that variable is set.
int MetalTestAppRun(NSString* title, void (^setUp)(MTKView* view));

// column-major 4x4 matrix helpers, matching Metal's float4x4 layout
void MetalTestMatrixIdentity(float m[16]);
void MetalTestMatrixMultiply(float out[16], const float a[16], const float b[16]);
void MetalTestMatrixPerspective(float m[16], float fovyRadians, float aspect, float nearZ, float farZ);
void MetalTestMatrixRotation(float m[16], float radians, float x, float y, float z);
void MetalTestMatrixTranslation(float m[16], float x, float y, float z);
