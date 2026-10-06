// MetalCube: a spinning cube with per-vertex colors, using the shaders from Indium's cube test.
// Exercises indexed drawing, a depth buffer created by MTKView, depth-stencil state, culling,
// and per-frame uniforms passed with setVertexBytes.

#import "../common/MetalTestApp.h"

#include <math.h>
#include <stdio.h>

// matches `Vertex` in the shader: float4 position [[position]]; float4 color;
typedef struct {
	float position[4];
	float color[4];
} CubeVertex;

static const CubeVertex cubeVertices[] = {
	{ { -1, -1, -1, 1 }, { 0, 0, 0, 1 } },
	{ {  1, -1, -1, 1 }, { 1, 0, 0, 1 } },
	{ {  1,  1, -1, 1 }, { 1, 1, 0, 1 } },
	{ { -1,  1, -1, 1 }, { 0, 1, 0, 1 } },
	{ { -1, -1,  1, 1 }, { 0, 0, 1, 1 } },
	{ {  1, -1,  1, 1 }, { 1, 0, 1, 1 } },
	{ {  1,  1,  1, 1 }, { 1, 1, 1, 1 } },
	{ { -1,  1,  1, 1 }, { 0, 1, 1, 1 } },
};

// counter-clockwise when seen from outside the cube
static const uint16_t cubeIndices[] = {
	4, 5, 6,  4, 6, 7, // +Z
	1, 0, 3,  1, 3, 2, // -Z
	5, 1, 2,  5, 2, 6, // +X
	0, 4, 7,  0, 7, 3, // -X
	7, 6, 2,  7, 2, 3, // +Y
	0, 1, 5,  0, 5, 4, // -Y
};

@interface CubeRenderer : NSObject <MTKViewDelegate>
- (instancetype)initWithView: (MTKView*)view;
@end

@implementation CubeRenderer
{
	id<MTLCommandQueue> _queue;
	id<MTLRenderPipelineState> _pipeline;
	id<MTLDepthStencilState> _depthState;
	id<MTLBuffer> _vertices;
	id<MTLBuffer> _indices;
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

	view.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
	view.clearColor = MTLClearColorMake(0.1, 0.1, 0.15, 1);

	id<MTLLibrary> library = [device newDefaultLibrary];
	MTLRenderPipelineDescriptor* desc = [MTLRenderPipelineDescriptor new];
	desc.vertexFunction = [library newFunctionWithName: @"vertex_project"];
	desc.fragmentFunction = [library newFunctionWithName: @"fragment_flatcolor"];
	desc.colorAttachments[0].pixelFormat = view.colorPixelFormat;
	desc.depthAttachmentPixelFormat = view.depthStencilPixelFormat;

	NSError* error = nil;
	_pipeline = [device newRenderPipelineStateWithDescriptor: desc error: &error];
	if (!_pipeline) {
		fprintf(stderr, "[MetalCube] couldn't create the pipeline: %s\n", [[error localizedDescription] UTF8String]);
		exit(1);
	}

	MTLDepthStencilDescriptor* depthDesc = [MTLDepthStencilDescriptor new];
	depthDesc.depthCompareFunction = MTLCompareFunctionLess;
	depthDesc.depthWriteEnabled = YES;
	_depthState = [device newDepthStencilStateWithDescriptor: depthDesc];

	_vertices = [device newBufferWithBytes: cubeVertices length: sizeof(cubeVertices) options: MTLResourceStorageModeShared];
	_indices = [device newBufferWithBytes: cubeIndices length: sizeof(cubeIndices) options: MTLResourceStorageModeShared];
	_queue = [device newCommandQueue];
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

	float angle = _frame * 0.02f;
	float projection[16], translation[16], rotationX[16], rotationY[16], model[16], mvp[16];
	MetalTestMatrixPerspective(projection, 65 * M_PI / 180, _size.width / _size.height, 0.1f, 100);
	MetalTestMatrixTranslation(translation, 0, 0, -5);
	MetalTestMatrixRotation(rotationX, angle * 0.7f, 1, 0, 0);
	MetalTestMatrixRotation(rotationY, angle, 0, 1, 0);
	MetalTestMatrixMultiply(model, rotationX, rotationY);
	MetalTestMatrixMultiply(model, translation, model);
	MetalTestMatrixMultiply(mvp, projection, model);

	id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor: pass];
	[encoder setRenderPipelineState: _pipeline];
	[encoder setDepthStencilState: _depthState];
	[encoder setFrontFacingWinding: MTLWindingCounterClockwise];
	[encoder setCullMode: MTLCullModeBack];
	[encoder setVertexBuffer: _vertices offset: 0 atIndex: 0];
	[encoder setVertexBytes: mvp length: sizeof(mvp) atIndex: 1];
	[encoder drawIndexedPrimitives: MTLPrimitiveTypeTriangle
	                    indexCount: sizeof(cubeIndices) / sizeof(cubeIndices[0])
	                     indexType: MTLIndexTypeUInt16
	                   indexBuffer: _indices
	             indexBufferOffset: 0];
	[encoder endEncoding];

	[commandBuffer presentDrawable: view.currentDrawable];
	[commandBuffer commit];

	if (_frame < 3 || _frame % 60 == 0) {
		fprintf(stderr, "[MetalCube] frame %lu\n", (unsigned long)_frame);
	}
	++_frame;
}

@end

int main(int argc, char** argv)
{
	return MetalTestAppRun(@"MetalCube", ^(MTKView* view) {
		// the view only keeps a weak reference to its delegate; this one lives as long as the app
		view.delegate = [[CubeRenderer alloc] initWithView: view];
	});
}
