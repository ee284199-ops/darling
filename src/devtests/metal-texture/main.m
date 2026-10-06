// MetalTexture: a slowly turning, lit quad with a checkerboard texture, using the shaders from Indium's
// texturing test. Exercises texture creation and upload, mipmap generation with a blit encoder, sampler
// states, and binding textures, samplers, and bytes to the fragment stage.

#import "../common/MetalTestApp.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

// matches the shader's packed `Vertex`: packed_float4 position, normal; packed_float2 texCoords
typedef struct {
	float position[4];
	float normal[4];
	float texCoords[2];
} QuadVertex;

// matches the shader's `Uniforms`: float4x4 modelViewProjectionMatrix, modelViewMatrix; float3x3 normalMatrix
// (a float3x3 is three float3 columns, each padded to 16 bytes)
typedef struct {
	float modelViewProjection[16];
	float modelView[16];
	float normal[12];
} QuadUniforms;

static const QuadVertex quadVertices[] = {
	{ { -1, -1, 0, 1 }, { 0, 0, 1, 0 }, { 0, 2 } },
	{ {  1, -1, 0, 1 }, { 0, 0, 1, 0 }, { 2, 2 } },
	{ {  1,  1, 0, 1 }, { 0, 0, 1, 0 }, { 2, 0 } },
	{ { -1, -1, 0, 1 }, { 0, 0, 1, 0 }, { 0, 2 } },
	{ {  1,  1, 0, 1 }, { 0, 0, 1, 0 }, { 2, 0 } },
	{ { -1,  1, 0, 1 }, { 0, 0, 1, 0 }, { 0, 0 } },
};

static const NSUInteger textureSize = 256;

@interface TextureRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithView: (MTKView*)view;
@end

@implementation TextureRenderer
{
	id<MTLCommandQueue> _queue;
	id<MTLRenderPipelineState> _pipeline;
	id<MTLBuffer> _vertices;
	id<MTLTexture> _texture;
	id<MTLSamplerState> _sampler;
	CGSize _size;
	NSUInteger _frame;
}

- (instancetype)initWithView: (MTKView*)view
{
	self = [super init];
	if (self == nil) {
		return nil;
	}

	id<MTLDevice> device = view.device;
	view.clearColor = MTLClearColorMake(0.2, 0.2, 0.25, 1);

	id<MTLLibrary> library = [device newDefaultLibrary];
	MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
	desc.vertexFunction = [library newFunctionWithName: @"vertex_project"];
	desc.fragmentFunction = [library newFunctionWithName: @"fragment_texture"];
	desc.colorAttachments[0].pixelFormat = view.colorPixelFormat;

	NSError* error = nil;
	_pipeline = [device newRenderPipelineStateWithDescriptor: desc error: &error];
	if (!_pipeline) {
		fprintf(stderr, "[MetalTexture] couldn't create the pipeline: %s\n", [[error localizedDescription] UTF8String]);
		exit(1);
	}

	_vertices = [device newBufferWithBytes: quadVertices length: sizeof(quadVertices) options: MTLResourceStorageModeShared];
	_queue = [device newCommandQueue];

	// an orange and blue checkerboard, with mipmaps generated on the GPU
	MTLTextureDescriptor* textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: MTLPixelFormatRGBA8Unorm width: textureSize height: textureSize mipmapped: YES];
	_texture = [device newTextureWithDescriptor: textureDesc];
	if (!_texture) {
		fprintf(stderr, "[MetalTexture] couldn't create the texture\n");
		exit(1);
	}
	fprintf(stderr, "[MetalTexture] texture: %lux%lu, %lu mipmap levels\n", (unsigned long)_texture.width, (unsigned long)_texture.height, (unsigned long)_texture.mipmapLevelCount);

	uint8_t* pixels = malloc(textureSize * textureSize * 4);
	for (NSUInteger y = 0; y < textureSize; ++y) {
		for (NSUInteger x = 0; x < textureSize; ++x) {
			uint8_t* pixel = &pixels[(y * textureSize + x) * 4];
			BOOL light = ((x / 32) + (y / 32)) % 2 == 0;
			pixel[0] = light ? 255 : 30;
			pixel[1] = light ? 140 : 90;
			pixel[2] = light ? 0 : 220;
			pixel[3] = 255;
		}
	}
	[_texture replaceRegion: MTLRegionMake2D(0, 0, textureSize, textureSize) mipmapLevel: 0 withBytes: pixels bytesPerRow: textureSize * 4];
	free(pixels);

	id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
	id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
	[blit generateMipmapsForTexture: _texture];
	[blit endEncoding];
	[commandBuffer commit];
	[commandBuffer waitUntilCompleted];

	MTLSamplerDescriptor* samplerDesc = [MTLSamplerDescriptor new];
	samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
	samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
	samplerDesc.mipFilter = MTLSamplerMipFilterLinear;
	samplerDesc.sAddressMode = MTLSamplerAddressModeRepeat;
	samplerDesc.tAddressMode = MTLSamplerAddressModeRepeat;
	samplerDesc.maxAnisotropy = 4;
	_sampler = [device newSamplerStateWithDescriptor: samplerDesc];
	if (!_sampler) {
		fprintf(stderr, "[MetalTexture] couldn't create the sampler state\n");
		exit(1);
	}

	_size = view.drawableSize;

	return self;
}

- (void)mtkView: (MTKView*)view drawableSizeWillChange: (CGSize)size
{
	_size = size;
}

- (void)drawInMTKView: (MTKView*)view
{
	MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
	if (!pass || _size.width < 1 || _size.height < 1) {
		return;
	}

	float projection[16], translation[16], rotation[16];
	QuadUniforms uniforms;
	MetalTestMatrixPerspective(projection, 60 * M_PI / 180, _size.width / _size.height, 0.1f, 100);
	MetalTestMatrixTranslation(translation, 0, 0, -2.6f);
	MetalTestMatrixRotation(rotation, 0.6f * sinf(_frame * 0.02f), 0, 1, 0);
	MetalTestMatrixMultiply(uniforms.modelView, translation, rotation);
	MetalTestMatrixMultiply(uniforms.modelViewProjection, projection, uniforms.modelView);

	// the model view matrix has no scaling, so its upper-left 3x3 is the normal matrix
	memset(uniforms.normal, 0, sizeof(uniforms.normal));
	for (int column = 0; column < 3; ++column) {
		for (int row = 0; row < 3; ++row) {
			uniforms.normal[column * 4 + row] = rotation[column * 4 + row];
		}
	}

	id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
	[encoder setRenderPipelineState: _pipeline];
	[encoder setVertexBuffer: _vertices offset: 0 atIndex: 0];
	[encoder setVertexBytes: &uniforms length: sizeof(uniforms) atIndex: 1];
	[encoder setFragmentBytes: &uniforms length: sizeof(uniforms) atIndex: 0];
	[encoder setFragmentTexture: _texture atIndex: 0];
	[encoder setFragmentSamplerState: _sampler atIndex: 0];
	[encoder drawPrimitives: MTLPrimitiveTypeTriangle vertexStart: 0 vertexCount: sizeof(quadVertices) / sizeof(quadVertices[0])];
	[encoder endEncoding];

	[commandBuffer presentDrawable: view.currentDrawable];
	[commandBuffer commit];

	if (_frame < 3 || _frame % 60 == 0) {
		fprintf(stderr, "[MetalTexture] frame %lu\n", (unsigned long)_frame);
	}
	++_frame;
}

@end

int main(int argc, char** argv)
{
	return MetalTestAppRun(@"MetalTexture", ^(MTKView* view) {
		// the view only keeps a weak reference to its delegate; this one lives as long as the app
		view.delegate = [[TextureRenderer alloc] initWithView: view];
	});
}
