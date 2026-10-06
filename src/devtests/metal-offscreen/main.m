// MetalOffscreen: renders into offscreen textures with the shaders from the triangle example, reads
// the results back with getBytes, and checks the pixels. Covers a plain render target, a 4x MSAA
// render with a resolve target, and a combined depth/stencil test. Needs no window; prints one PASS
// line per case and exits non-zero on failure.

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

static id<MTLRenderPipelineState> makePipeline(id<MTLDevice> device, id<MTLLibrary> library,
                                               MTLPixelFormat colorFormat,
                                               MTLPixelFormat depthStencilFormat,
                                               NSUInteger rasterSampleCount,
                                               NSError** error)
{
	MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
	descriptor.vertexFunction = [library newFunctionWithName: @"vertexShader"];
	descriptor.fragmentFunction = [library newFunctionWithName: @"fragmentShader"];
	descriptor.colorAttachments[0].pixelFormat = colorFormat;
	descriptor.depthAttachmentPixelFormat = depthStencilFormat;
	descriptor.stencilAttachmentPixelFormat = depthStencilFormat;
	descriptor.rasterSampleCount = rasterSampleCount;
	descriptor.sampleCount = rasterSampleCount;

	return [[device newRenderPipelineStateWithDescriptor: descriptor error: error] autorelease];
}

static void encodeTriangle(id<MTLRenderCommandEncoder> encoder, id<MTLRenderPipelineState> pipeline,
                           const AAPLVertex* vertices, NSUInteger vertexCount,
                           NSUInteger width, NSUInteger height)
{
	vector_uint2 viewportSize = { (uint32_t)width, (uint32_t)height };

	[encoder setViewport: (MTLViewport){ 0, 0, (double)width, (double)height, 0, 1 }];
	[encoder setRenderPipelineState: pipeline];
	[encoder setVertexBytes: vertices length: sizeof(AAPLVertex) * vertexCount atIndex: AAPLVertexInputIndexVertices];
	[encoder setVertexBytes: &viewportSize length: sizeof(viewportSize) atIndex: AAPLVertexInputIndexViewportSize];
	[encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: vertexCount];
}

static BOOL waitForCommandBuffer(id<MTLCommandBuffer> commandBuffer, const char* what, int* failures)
{
	[commandBuffer commit];
	[commandBuffer waitUntilCompleted];

	if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
		fprintf(stderr, "FAIL: %s: command buffer status is %lu instead of completed\n", what, (unsigned long)commandBuffer.status);
		++*failures;
		return NO;
	}

	return YES;
}

//
// case 1: plain render target
//

static int runBasicCase(id<MTLDevice> device, id<MTLLibrary> library, id<MTLCommandQueue> queue,
                        NSUInteger size, NSUInteger pixelBytes, const AAPLVertex* redTriangle)
{
	int failures = 0;
	NSError* error = nil;
	id<MTLRenderPipelineState> pipeline = makePipeline(device, library, MTLPixelFormatBGRA8Unorm, MTLPixelFormatInvalid, 1, &error);
	if (!pipeline) {
		return fail("couldn't create the basic render pipeline", error);
	}

	MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
	textureDescriptor.storageMode = MTLStorageModeShared;
	textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

	id<MTLTexture> texture = [device newTextureWithDescriptor: textureDescriptor];
	if (!texture) {
		return fail("couldn't create the offscreen texture", nil);
	}

	id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

	MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = texture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);

	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
	encodeTriangle(encoder, pipeline, redTriangle, 3, size, size);
	[encoder endEncoding];

	if (!waitForCommandBuffer(commandBuffer, "basic", &failures)) {
		[texture release];
		return 1;
	}

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
	[texture release];

	if (failures > 0) {
		fprintf(stderr, "%d checks failed\n", failures);
		return fail("offscreen render was not read back correctly", nil);
	}

	printf("PASS: offscreen render read back correctly\n");
	return 0;
}

//
// case 2: 4x multisampling with a resolve target
//

static int runMSAACase(id<MTLDevice> device, id<MTLLibrary> library, id<MTLCommandQueue> queue,
                       NSUInteger size, NSUInteger pixelBytes, const AAPLVertex* redTriangle)
{
	int failures = 0;
	const NSUInteger sampleCount = 4;
	NSError* error = nil;
	id<MTLRenderPipelineState> pipeline = makePipeline(device, library, MTLPixelFormatBGRA8Unorm, MTLPixelFormatInvalid, sampleCount, &error);
	if (!pipeline) {
		return fail("couldn't create the MSAA render pipeline", error);
	}

	MTLTextureDescriptor* multisampleDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
	multisampleDescriptor.textureType = MTLTextureType2DMultisample;
	multisampleDescriptor.sampleCount = sampleCount;
	multisampleDescriptor.storageMode = MTLStorageModePrivate;
	multisampleDescriptor.usage = MTLTextureUsageRenderTarget;

	id<MTLTexture> multisampleTexture = [device newTextureWithDescriptor: multisampleDescriptor];
	if (!multisampleTexture) {
		return fail("couldn't create the multisample texture", nil);
	}

	MTLTextureDescriptor* resolveDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
	resolveDescriptor.storageMode = MTLStorageModeShared;
	resolveDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

	id<MTLTexture> resolveTexture = [device newTextureWithDescriptor: resolveDescriptor];
	if (!resolveTexture) {
		[multisampleTexture release];
		return fail("couldn't create the resolve texture", nil);
	}

	id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

	MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = multisampleTexture;
	pass.colorAttachments[0].resolveTexture = resolveTexture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);

	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
	encodeTriangle(encoder, pipeline, redTriangle, 3, size, size);
	[encoder endEncoding];

	if (!waitForCommandBuffer(commandBuffer, "MSAA", &failures)) {
		[multisampleTexture release];
		[resolveTexture release];
		return 1;
	}

	const NSUInteger fullRow = size * pixelBytes;
	uint8_t* pixels = (uint8_t*)malloc(fullRow * size);

	[resolveTexture getBytes: pixels bytesPerRow: fullRow fromRegion: MTLRegionMake2D(0, 0, size, size) mipmapLevel: 0];

	checkPixel(pixels, fullRow, 32, 32, 0, 0, 255, 255, "MSAA center", &failures);
	checkPixel(pixels, fullRow, 0, 0, 255, 0, 0, 255, "MSAA top-left", &failures);
	checkPixel(pixels, fullRow, 63, 63, 255, 0, 0, 255, "MSAA bottom-right", &failures);

	// count partially-covered edge pixels: their red and blue channels are both mid-range.
	// this can only happen with multisampling (single-sampled edges are pure red or pure blue).
	NSUInteger antialiased = 0;
	for (NSUInteger y = 12; y <= 52; ++y) {
		for (NSUInteger x = 0; x < size; ++x) {
			const uint8_t* pixel = pixels + y * fullRow + x * 4;
			if (pixel[2] > 30 && pixel[2] < 225 && pixel[0] > 30 && pixel[0] < 225) {
				++antialiased;
			}
		}
	}
	printf("MSAA anti-aliased edge pixels: %lu\n", (unsigned long)antialiased);
	if (antialiased == 0) {
		fprintf(stderr, "FAIL: no anti-aliased edge pixels found\n");
		++failures;
	}

	free(pixels);
	[multisampleTexture release];
	[resolveTexture release];

	if (failures > 0) {
		fprintf(stderr, "%d MSAA checks failed\n", failures);
		return fail("MSAA render was not resolved and read back correctly", nil);
	}

	printf("PASS: MSAA render resolve read back correctly\n");
	return 0;
}

//
// case 3: depth/stencil (stencil test culls the second draw)
//

static int runStencilCase(id<MTLDevice> device, id<MTLLibrary> library, id<MTLCommandQueue> queue,
                          NSUInteger size, NSUInteger pixelBytes, const AAPLVertex* redTriangle)
{
	int failures = 0;
	const MTLPixelFormat depthStencilFormat = MTLPixelFormatDepth32Float_Stencil8;
	NSError* error = nil;
	id<MTLRenderPipelineState> pipeline = makePipeline(device, library, MTLPixelFormatBGRA8Unorm, depthStencilFormat, 1, &error);
	if (!pipeline) {
		return fail("couldn't create the stencil render pipeline", error);
	}

	MTLTextureDescriptor* colorDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
	colorDescriptor.storageMode = MTLStorageModeShared;
	colorDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;

	id<MTLTexture> colorTexture = [device newTextureWithDescriptor: colorDescriptor];
	if (!colorTexture) {
		return fail("couldn't create the stencil color texture", nil);
	}

	MTLTextureDescriptor* depthStencilDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: depthStencilFormat width: size height: size mipmapped: NO];
	depthStencilDescriptor.storageMode = MTLStorageModePrivate;
	depthStencilDescriptor.usage = MTLTextureUsageRenderTarget;

	id<MTLTexture> depthStencilTexture = [device newTextureWithDescriptor: depthStencilDescriptor];
	if (!depthStencilTexture) {
		[colorTexture release];
		return fail("couldn't create the depth/stencil texture", nil);
	}

	// pass 1 state: always pass, write 1 into the stencil buffer wherever the triangle covers
	MTLDepthStencilDescriptor* markDescriptor = [MTLDepthStencilDescriptor new];
	markDescriptor.depthCompareFunction = MTLCompareFunctionAlways;
	markDescriptor.depthWriteEnabled = NO;
	markDescriptor.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
	markDescriptor.frontFaceStencil.depthStencilPassOperation = MTLStencilOperationReplace;
	markDescriptor.frontFaceStencil.readMask = 0xFF;
	markDescriptor.frontFaceStencil.writeMask = 0xFF;
	markDescriptor.backFaceStencil.stencilCompareFunction = MTLCompareFunctionAlways;
	markDescriptor.backFaceStencil.depthStencilPassOperation = MTLStencilOperationReplace;
	markDescriptor.backFaceStencil.readMask = 0xFF;
	markDescriptor.backFaceStencil.writeMask = 0xFF;
	id<MTLDepthStencilState> markState = [device newDepthStencilStateWithDescriptor: markDescriptor];

	// pass 2 state: only draw where the stencil is still 1 (i.e. inside the first triangle)
	MTLDepthStencilDescriptor* testDescriptor = [MTLDepthStencilDescriptor new];
	testDescriptor.depthCompareFunction = MTLCompareFunctionAlways;
	testDescriptor.depthWriteEnabled = NO;
	testDescriptor.frontFaceStencil.stencilCompareFunction = MTLCompareFunctionEqual;
	testDescriptor.frontFaceStencil.stencilFailureOperation = MTLStencilOperationKeep;
	testDescriptor.frontFaceStencil.depthFailureOperation = MTLStencilOperationKeep;
	testDescriptor.frontFaceStencil.depthStencilPassOperation = MTLStencilOperationKeep;
	testDescriptor.frontFaceStencil.readMask = 0xFF;
	testDescriptor.backFaceStencil.stencilCompareFunction = MTLCompareFunctionEqual;
	testDescriptor.backFaceStencil.stencilFailureOperation = MTLStencilOperationKeep;
	testDescriptor.backFaceStencil.depthFailureOperation = MTLStencilOperationKeep;
	testDescriptor.backFaceStencil.depthStencilPassOperation = MTLStencilOperationKeep;
	testDescriptor.backFaceStencil.readMask = 0xFF;
	id<MTLDepthStencilState> testState = [device newDepthStencilStateWithDescriptor: testDescriptor];

	// a huge green triangle that covers the whole target wherever the stencil allows it
	static const AAPLVertex greenCover[] = {
		{ { -100, -100 }, { 0, 1, 0, 1 } },
		{ {  300, -100 }, { 0, 1, 0, 1 } },
		{ { -100,  300 }, { 0, 1, 0, 1 } },
	};

	id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

	MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = colorTexture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1);
	pass.depthAttachment.texture = depthStencilTexture;
	pass.depthAttachment.loadAction = MTLLoadActionClear;
	pass.depthAttachment.storeAction = MTLStoreActionDontCare;
	pass.depthAttachment.clearDepth = 1;
	pass.stencilAttachment.texture = depthStencilTexture;
	pass.stencilAttachment.loadAction = MTLLoadActionClear;
	pass.stencilAttachment.storeAction = MTLStoreActionDontCare;
	pass.stencilAttachment.clearStencil = 0;

	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];

	// pass 1: mark the first triangle in the stencil buffer
	[encoder setDepthStencilState: markState];
	[encoder setStencilReferenceValue: 1];
	encodeTriangle(encoder, pipeline, redTriangle, 3, size, size);

	// pass 2: the green triangle only survives where the stencil equals 1
	[encoder setDepthStencilState: testState];
	[encoder setStencilReferenceValue: 1];
	encodeTriangle(encoder, pipeline, greenCover, 3, size, size);

	[encoder endEncoding];

	if (!waitForCommandBuffer(commandBuffer, "stencil", &failures)) {
		[colorTexture release];
		[depthStencilTexture release];
		return 1;
	}

	const NSUInteger fullRow = size * pixelBytes;
	uint8_t* pixels = (uint8_t*)malloc(fullRow * size);

	[colorTexture getBytes: pixels bytesPerRow: fullRow fromRegion: MTLRegionMake2D(0, 0, size, size) mipmapLevel: 0];

	checkPixel(pixels, fullRow, 32, 32, 0, 255, 0, 255, "stencil center (inside)", &failures);
	checkPixel(pixels, fullRow, 0, 0, 255, 0, 0, 255, "stencil top-left (outside)", &failures);
	checkPixel(pixels, fullRow, 63, 63, 255, 0, 0, 255, "stencil bottom-right (outside)", &failures);
	checkPixel(pixels, fullRow, 32, 56, 255, 0, 0, 255, "stencil below the base (outside)", &failures);

	free(pixels);
	[colorTexture release];
	[depthStencilTexture release];

	if (failures > 0) {
		fprintf(stderr, "%d stencil checks failed\n", failures);
		return fail("stencil render was not read back correctly", nil);
	}

	printf("PASS: stencil render read back correctly\n");
	return 0;
}

int main(int argc, char** argv)
{
	// progress output must survive a crash even when stdout is a pipe
	setvbuf(stdout, NULL, _IOLBF, 0);

	int failures = 0;

	@autoreleasepool {
		id<MTLDevice> device = [MTLCreateSystemDefaultDevice() autorelease];
		if (!device) {
			return fail("no Metal device", nil);
		}

		id<MTLLibrary> library = [[device newDefaultLibrary] autorelease];
		if (!library) {
			return fail("couldn't load default.metallib", nil);
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];

		const NSUInteger size = 64;
		const NSUInteger pixelBytes = 4;

		// all three vertices are opaque red; the pixel-space positions put the triangle near the middle
		static const AAPLVertex redTriangle[] = {
			{ { -20, -20 }, { 1, 0, 0, 1 } },
			{ {  20, -20 }, { 1, 0, 0, 1 } },
			{ {   0,  20 }, { 1, 0, 0, 1 } },
		};

		failures += runBasicCase(device, library, queue, size, pixelBytes, redTriangle);
		failures += runMSAACase(device, library, queue, size, pixelBytes, redTriangle);
		failures += runStencilCase(device, library, queue, size, pixelBytes, redTriangle);
	}

	return failures ? 1 : 0;
}