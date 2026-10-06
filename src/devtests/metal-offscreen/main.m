// MetalOffscreen: renders one triangle into a 64x64 offscreen texture with the shaders from the
// triangle example, reads the result back with getBytes, and checks the pixels. Needs no window;
// prints PASS or FAIL and exits non-zero on failure.

#import <Metal/Metal.h>
#import "AAPLShaderTypes.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fail(const char* what, NSError* error)
{
	fprintf(stderr, "FAIL: %s%s%s\n", what, error ? ": " : "", error ? [[error localizedDescription] UTF8String] : "");
	return 1;
}

// Pixels are stored as BGRA bytes; `b`, `g`, `r` and `a` are the expected values.
static void checkPixel(const uint8_t* bytes, NSUInteger bytesPerRow, NSUInteger x, NSUInteger y,
                       int b, int g, int r, int a, const char* what, int* failures)
{
	const uint8_t* pixel = bytes + y * bytesPerRow + x * 4;

	printf("%s: pixel (%lu,%lu) = B:%u G:%u R:%u A:%u\n",
		what, (unsigned long)x, (unsigned long)y, pixel[0], pixel[1], pixel[2], pixel[3]);

	if (abs((int)pixel[0] - b) > 2 || abs((int)pixel[1] - g) > 2 ||
	    abs((int)pixel[2] - r) > 2 || abs((int)pixel[3] - a) > 2) {
		fprintf(stderr, "FAIL: %s at (%lu,%lu) is B:%u G:%u R:%u A:%u, expected B:%d G:%d R:%d A:%d\n",
			what, (unsigned long)x, (unsigned long)y, pixel[0], pixel[1], pixel[2], pixel[3], b, g, r, a);
		++*failures;
	}
}

int main(int argc, char** argv)
{
	// progress output must survive a crash even when stdout is a pipe
	setvbuf(stdout, NULL, _IOLBF, 0);

	@autoreleasepool {
		id<MTLDevice> device = [MTLCreateSystemDefaultDevice() autorelease];
		if (!device) {
			return fail("no Metal device", nil);
		}

		const NSUInteger size = 64;
		const NSUInteger pixelBytes = 4;

		id<MTLLibrary> library = [[device newDefaultLibrary] autorelease];
		if (!library) {
			return fail("couldn't load default.metallib", nil);
		}

		id<MTLFunction> vertexFunction = [[library newFunctionWithName: @"vertexShader"] autorelease];
		id<MTLFunction> fragmentFunction = [[library newFunctionWithName: @"fragmentShader"] autorelease];
		if (!vertexFunction || !fragmentFunction) {
			return fail("missing vertexShader/fragmentShader in the library", nil);
		}

		NSError* error = nil;
		MTLRenderPipelineDescriptor* pipelineDescriptor = [MTLRenderPipelineDescriptor new];
		pipelineDescriptor.vertexFunction = vertexFunction;
		pipelineDescriptor.fragmentFunction = fragmentFunction;
		pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

		id<MTLRenderPipelineState> pipeline = [[device newRenderPipelineStateWithDescriptor: pipelineDescriptor error: &error] autorelease];
		if (!pipeline) {
			return fail("couldn't create the render pipeline", error);
		}

		MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
		textureDescriptor.storageMode = MTLStorageModeShared;
		textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

		id<MTLTexture> texture = [device newTextureWithDescriptor: textureDescriptor];
		if (!texture) {
			return fail("couldn't create the offscreen texture", nil);
		}

		// all three vertices are opaque red; the pixel-space positions put the triangle near the middle
		static const AAPLVertex triangleVertices[] = {
			{ { -20, -20 }, { 1, 0, 0, 1 } },
			{ {  20, -20 }, { 1, 0, 0, 1 } },
			{ {   0,  20 }, { 1, 0, 0, 1 } },
		};
		vector_uint2 viewportSize = { (uint32_t)size, (uint32_t)size };

		id<MTLCommandQueue> queue = [device newCommandQueue];
		id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

		MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
		pass.colorAttachments[0].texture = texture;
		pass.colorAttachments[0].loadAction = MTLLoadActionClear;
		pass.colorAttachments[0].storeAction = MTLStoreActionStore;
		pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);

		id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
		[encoder setViewport: (MTLViewport){ 0, 0, (double)size, (double)size, 0, 1 }];
		[encoder setRenderPipelineState: pipeline];
		[encoder setVertexBytes: triangleVertices length: sizeof(triangleVertices) atIndex: AAPLVertexInputIndexVertices];
		[encoder setVertexBytes: &viewportSize length: sizeof(viewportSize) atIndex: AAPLVertexInputIndexViewportSize];
		[encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: 3];
		[encoder endEncoding];

		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];

		if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
			fprintf(stderr, "command buffer status is %lu instead of completed\n", (unsigned long)commandBuffer.status);
			return fail("wrong command buffer status", nil);
		}

		int failures = 0;
		const NSUInteger fullRow = size * pixelBytes;
		uint8_t* pixels = (uint8_t*)malloc(fullRow * size);

		[texture getBytes: pixels bytesPerRow: fullRow fromRegion: MTLRegionMake2D(0, 0, size, size) mipmapLevel: 0];

		// row 0 is the top; the apex at pixel y=+20 lands on row 12 and the base on row 52
		checkPixel(pixels, fullRow, 32, 32, 0, 0, 255, 255, "inside the triangle", &failures);
		checkPixel(pixels, fullRow, 32, 16, 0, 0, 255, 255, "near the apex", &failures);
		checkPixel(pixels, fullRow, 32, 56, 255, 0, 0, 255, "below the base", &failures);
		checkPixel(pixels, fullRow, 0, 0, 255, 0, 0, 255, "top-left corner", &failures);
		checkPixel(pixels, fullRow, 63, 63, 255, 0, 0, 255, "bottom-right corner", &failures);
		checkPixel(pixels, fullRow, 2, 40, 255, 0, 0, 255, "outside the left edge", &failures);

		free(pixels);

		// now read back only a 16x16 region with a padded bytesPerRow and make sure the padding is untouched
		const NSUInteger regionOrigin = 24;
		const NSUInteger regionSize = 16;
		const NSUInteger paddedRow = 100;
		const NSUInteger paddedLength = (regionSize - 1) * paddedRow + regionSize * pixelBytes;
		uint8_t* padded = (uint8_t*)malloc(paddedLength);
		memset(padded, 0xAB, paddedLength);

		[texture getBytes: padded bytesPerRow: paddedRow fromRegion: MTLRegionMake2D(regionOrigin, regionOrigin, regionSize, regionSize) mipmapLevel: 0];

		checkPixel(padded, paddedRow, 8, 8, 0, 0, 255, 255, "padded readback center", &failures);

		BOOL paddingIntact = YES;
		for (NSUInteger y = 0; y < regionSize - 1; ++y) {
			for (NSUInteger x = regionSize * pixelBytes; x < paddedRow; ++x) {
				if (padded[y * paddedRow + x] != 0xAB) {
					paddingIntact = NO;
				}
			}
		}
		printf("padded readback: the bytesPerRow padding %s\n", paddingIntact ? "was left untouched" : "was overwritten");
		if (!paddingIntact) {
			fprintf(stderr, "FAIL: readback wrote into the bytesPerRow padding\n");
			++failures;
		}

		free(padded);

		if (failures > 0) {
			fprintf(stderr, "%d checks failed\n", failures);
			return fail("offscreen render was not read back correctly", nil);
		}

		printf("PASS: offscreen render read back correctly\n");
	}
	return 0;
}