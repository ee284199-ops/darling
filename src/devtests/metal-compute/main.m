// MetalCompute: runs the add_arrays kernel from Indium's basic-compute test and checks every result,
// after a few of the device queries apps commonly make at startup. Needs no window; prints PASS or FAIL.

#import <Metal/Metal.h>
#include <math.h>
#include <stdio.h>

static int fail(const char* what, NSError* error)
{
	fprintf(stderr, "FAIL: %s%s%s\n", what, error ? ": " : "", error ? [[error localizedDescription] UTF8String] : "");
	return 1;
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

		MTLSize maxThreads = device.maxThreadsPerThreadgroup;
		printf("device: %s (registry ID %#llx)\n", [device.name UTF8String], (unsigned long long)device.registryID);
		printf("Mac2 family: %d, Apple7 family: %d, max threads per threadgroup: %lux%lux%lu\n",
			[device supportsFamily: MTLGPUFamilyMac2], [device supportsFamily: MTLGPUFamilyApple7],
			(unsigned long)maxThreads.width, (unsigned long)maxThreads.height, (unsigned long)maxThreads.depth);

		NSError* error = nil;
		if ([device newLibraryWithSource: @"kernel void k() {}" options: nil error: &error] != nil || error == nil) {
			return fail("compiling shader source should report an error", nil);
		}
		printf("compiling from source is refused as expected: %s\n", [[error localizedDescription] UTF8String]);
		error = nil;

		id<MTLLibrary> library = [[device newDefaultLibrary] autorelease];
		if (!library) {
			return fail("couldn't load default.metallib", nil);
		}

		id<MTLFunction> function = [[library newFunctionWithName: @"add_arrays"] autorelease];
		if (!function) {
			return fail("no add_arrays function in the library", nil);
		}

		id<MTLComputePipelineState> pipeline = [[device newComputePipelineStateWithFunction: function error: &error] autorelease];
		if (!pipeline) {
			return fail("couldn't create the compute pipeline", error);
		}

		const NSUInteger count = 1 << 16;
		const NSUInteger length = count * sizeof(float);
		id<MTLBuffer> inA = [[device newBufferWithLength: length options: MTLResourceStorageModeShared] autorelease];
		id<MTLBuffer> inB = [[device newBufferWithLength: length options: MTLResourceStorageModeShared] autorelease];
		id<MTLBuffer> result = [[device newBufferWithLength: length options: MTLResourceStorageModeShared] autorelease];

		float* a = (float*)inA.contents;
		float* b = (float*)inB.contents;
		for (NSUInteger i = 0; i < count; ++i) {
			a[i] = (float)i;
			b[i] = 2.0f * i + 0.5f;
		}

		id<MTLCommandQueue> queue = [[device newCommandQueue] autorelease];
		id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];

		if (commandBuffer.commandQueue != queue) {
			return fail("commandBuffer.commandQueue doesn't return its queue", nil);
		}

		// fill the output with 0xff bytes (NaNs) first, so a kernel that writes nothing can't pass
		id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
		[blit fillBuffer: result range: NSMakeRange(0, length) value: 0xff];
		[blit endEncoding];

		id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
		[encoder pushDebugGroup: @"add arrays"];
		[encoder setComputePipelineState: pipeline];
		[encoder setBuffer: inA offset: 0 atIndex: 0];
		[encoder setBuffer: inB offset: 0 atIndex: 1];
		[encoder setBuffer: result offset: 0 atIndex: 2];
		[encoder dispatchThreads: MTLSizeMake(count, 1, 1) threadsPerThreadgroup: MTLSizeMake(64, 1, 1)];
		[encoder popDebugGroup];
		[encoder endEncoding];

		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];

		if (commandBuffer.status != MTLCommandBufferStatusCompleted) {
			fprintf(stderr, "command buffer status is %lu instead of completed\n", (unsigned long)commandBuffer.status);
			return fail("wrong command buffer status", nil);
		}

		const float* sums = (const float*)result.contents;
		NSUInteger mismatches = 0;
		for (NSUInteger i = 0; i < count; ++i) {
			if (sums[i] != a[i] + b[i]) {
				if (mismatches < 5) {
					fprintf(stderr, "result[%lu] = %f, expected %f\n", (unsigned long)i, sums[i], a[i] + b[i]);
				}
				++mismatches;
			}
		}

		if (mismatches > 0) {
			fprintf(stderr, "%lu of %lu results are wrong\n", (unsigned long)mismatches, (unsigned long)count);
			return fail("wrong results", nil);
		}

		printf("PASS: %lu sums computed on the GPU\n", (unsigned long)count);
	}
	return 0;
}
