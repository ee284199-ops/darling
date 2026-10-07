// MetalVertexInput: renders a triangle offscreen with the skybox shaders from Indium's cubemap test,
// whose vertex function reads `float4 position [[attribute(0)]]` and `float4 normal [[attribute(1)]]`
// through [[stage_in]]. The position comes second in each vertex (attribute offset 16), so the
// triangle only appears where it should if the vertex descriptor's offsets, stride and buffer index
// reach the pipeline. The fragment function samples a cube texture that is green on every face.
// Needs no window; prints PASS or FAIL and exits non-zero on failure.

#import <Metal/Metal.h>

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	float normal[4];
	float position[4];
} Vertex;

// matches `struct Uniforms` in the cubemap shaders
typedef struct {
	float modelMatrix[16];
	float projectionMatrix[16];
	float normalMatrix[16];
	float modelViewProjectionMatrix[16];
	float worldCameraPosition[4];
} Uniforms;

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

static void setIdentity(float* matrix)
{
	memset(matrix, 0, sizeof(float) * 16);
	matrix[0] = matrix[5] = matrix[10] = matrix[15] = 1;
}

int main(int argc, const char** argv)
{
	@autoreleasepool {
		const NSUInteger size = 64;
		int failures = 0;
		NSError* error = nil;

		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device) {
			return fail("no Metal device", nil);
		}

		id<MTLLibrary> library = [device newDefaultLibrary];
		if (!library) {
			return fail("couldn't load default.metallib", nil);
		}

		MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
		vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
		vertexDescriptor.attributes[0].offset = offsetof(Vertex, position);
		vertexDescriptor.attributes[0].bufferIndex = 0;
		vertexDescriptor.attributes[1].format = MTLVertexFormatFloat4;
		vertexDescriptor.attributes[1].offset = offsetof(Vertex, normal);
		vertexDescriptor.attributes[1].bufferIndex = 0;
		vertexDescriptor.layouts[0].stride = sizeof(Vertex);
		vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
		vertexDescriptor.layouts[0].stepRate = 1;

		// the pipeline descriptor keeps a copy; changing ours afterwards must not affect it
		MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor new] autorelease];
		pipelineDescriptor.vertexFunction = [[library newFunctionWithName: @"vertex_skybox"] autorelease];
		pipelineDescriptor.fragmentFunction = [[library newFunctionWithName: @"fragment_cube_lookup"] autorelease];
		pipelineDescriptor.vertexDescriptor = vertexDescriptor;
		pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
		vertexDescriptor.attributes[0].offset = offsetof(Vertex, normal);

		if (pipelineDescriptor.vertexDescriptor.attributes[0].offset != offsetof(Vertex, position)) {
			fprintf(stderr, "FAIL: the pipeline descriptor's vertex descriptor changed with the original\n");
			++failures;
		}

		id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor: pipelineDescriptor error: &error];
		if (!pipeline) {
			return fail("couldn't create the render pipeline", error);
		}

		// a 1x1 cube texture that is green on every face
		MTLTextureDescriptor* cubeDescriptor = [MTLTextureDescriptor textureCubeDescriptorWithPixelFormat: MTLPixelFormatRGBA8Unorm size: 1 mipmapped: NO];
		id<MTLTexture> cubeTexture = [device newTextureWithDescriptor: cubeDescriptor];
		const uint8_t green[4] = { 0, 255, 0, 255 };
		for (NSUInteger face = 0; face < 6; ++face) {
			[cubeTexture replaceRegion: MTLRegionMake2D(0, 0, 1, 1) mipmapLevel: 0 slice: face withBytes: green bytesPerRow: 4 bytesPerImage: 4];
		}

		id<MTLSamplerState> sampler = [device newSamplerStateWithDescriptor: [[MTLSamplerDescriptor new] autorelease]];

		// the triangle covers the middle of the target; normals are junk that would make a visible
		// mess if they were read as positions
		const Vertex vertices[3] = {
			{ { 9, 9, 9, 0 }, { -0.5f, -0.5f, 0, 1 } },
			{ { 9, 9, 9, 0 }, {  0.5f, -0.5f, 0, 1 } },
			{ { 9, 9, 9, 0 }, {  0.0f,  0.5f, 0, 1 } },
		};
		id<MTLBuffer> vertexBuffer = [device newBufferWithBytes: vertices length: sizeof(vertices) options: MTLResourceStorageModeShared];

		Uniforms uniforms;
		memset(&uniforms, 0, sizeof(uniforms));
		setIdentity(uniforms.modelMatrix);
		setIdentity(uniforms.projectionMatrix);
		setIdentity(uniforms.normalMatrix);
		setIdentity(uniforms.modelViewProjectionMatrix);

		MTLTextureDescriptor* targetDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatBGRA8Unorm width: size height: size mipmapped: NO];
		targetDescriptor.storageMode = MTLStorageModeShared;
		targetDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
		id<MTLTexture> target = [device newTextureWithDescriptor: targetDescriptor];

		id<MTLCommandQueue> queue = [device newCommandQueue];
		id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

		MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
		pass.colorAttachments[0].texture = target;
		pass.colorAttachments[0].loadAction = MTLLoadActionClear;
		pass.colorAttachments[0].storeAction = MTLStoreActionStore;
		pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1);

		id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
		[encoder setViewport: (MTLViewport){ 0, 0, (double)size, (double)size, 0, 1 }];
		[encoder setRenderPipelineState: pipeline];
		[encoder setVertexBuffer: vertexBuffer offset: 0 atIndex: 0];
		[encoder setVertexBytes: &uniforms length: sizeof(uniforms) atIndex: 1];
		[encoder setFragmentBytes: &uniforms length: sizeof(uniforms) atIndex: 0];
		[encoder setFragmentTexture: cubeTexture atIndex: 0];
		[encoder setFragmentSamplerState: sampler atIndex: 0];
		[encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: 3];
		[encoder endEncoding];

		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];
		if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
			return fail("the command buffer didn't complete", commandBuffer.error);
		}

		const NSUInteger bytesPerRow = size * 4;
		uint8_t* pixels = (uint8_t*)malloc(bytesPerRow * size);
		[target getBytes: pixels bytesPerRow: bytesPerRow fromRegion: MTLRegionMake2D(0, 0, size, size) mipmapLevel: 0];

		// clip space y=+0.5 is row 16 from the top and y=-0.5 is row 48
		checkPixel(pixels, bytesPerRow, 32, 32, 0, 255, 0, 255, "inside the triangle", &failures);
		checkPixel(pixels, bytesPerRow, 32, 20, 0, 255, 0, 255, "near the apex", &failures);
		checkPixel(pixels, bytesPerRow, 32, 56, 0, 0, 255, 255, "below the base", &failures);
		checkPixel(pixels, bytesPerRow, 2, 2, 0, 0, 255, 255, "top-left corner", &failures);
		checkPixel(pixels, bytesPerRow, 61, 61, 0, 0, 255, 255, "bottom-right corner", &failures);

		free(pixels);
		[target release];
		[vertexBuffer release];
		[sampler release];
		[cubeTexture release];
		[pipeline release];
		[queue release];
		[library release];
		[device release];

		if (failures > 0) {
			fprintf(stderr, "%d checks failed\n", failures);
			return fail("the triangle drawn through the vertex descriptor is wrong", nil);
		}

		printf("PASS: vertex input through an MTLVertexDescriptor\n");
		return 0;
	}
}
