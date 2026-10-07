// Checks the CoreAudio paths apps use: the default output device, an AudioQueue, a default
// output AudioUnit and an AUGraph pulling silence (nothing audible), AudioConverter sample rate
// and format conversion, and AudioFile / ExtAudioFile writing and reading a WAV file.

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures = 0;

static void expect(int condition, const char* what) {
	printf("%s: %s\n", condition ? "PASS" : "FAIL", what);
	if (!condition)
		failures++;
}

static void expectNoErr(OSStatus status, const char* what) {
	char line[256];

	snprintf(line, sizeof(line), "%s (status %d)", what, (int) status);
	expect(status == noErr, line);
}

static AudioStreamBasicDescription floatStereo(Float64 rate) {
	AudioStreamBasicDescription format;

	memset(&format, 0, sizeof(format));
	format.mSampleRate = rate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	format.mChannelsPerFrame = 2;
	format.mBitsPerChannel = 32;
	format.mFramesPerPacket = 1;
	format.mBytesPerFrame = 8;
	format.mBytesPerPacket = 8;
	return format;
}

static AudioStreamBasicDescription int16(Float64 rate, UInt32 channels) {
	AudioStreamBasicDescription format;

	memset(&format, 0, sizeof(format));
	format.mSampleRate = rate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mChannelsPerFrame = channels;
	format.mBitsPerChannel = 16;
	format.mFramesPerPacket = 1;
	format.mBytesPerFrame = 2 * channels;
	format.mBytesPerPacket = 2 * channels;
	return format;
}

static void checkDevice(void) {
	AudioObjectPropertyAddress address = {
		kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster
	};
	AudioDeviceID device = kAudioObjectUnknown;
	UInt32 size = sizeof(device);
	OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);

	expectNoErr(status, "the default output device can be asked for");
	expect(device != kAudioObjectUnknown, "there is a default output device");

	if (device != kAudioObjectUnknown) {
		Float64 rate = 0;
		AudioObjectPropertyAddress rateAddress = {
			kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster
		};
		size = sizeof(rate);
		status = AudioObjectGetPropertyData(device, &rateAddress, 0, NULL, &size, &rate);
		printf("  default output device %u, nominal rate %.0f\n", (unsigned) device, rate);
		expect(status == noErr && rate > 0, "the device has a sample rate");
	}

	AudioComponentDescription description = {
		kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0
	};
	expect(AudioComponentFindNext(NULL, &description) != NULL, "the default output AudioUnit component exists");
}

// ---------------------------------------------------------------- AudioQueue

#ifndef CHECK_QUEUE
#define CHECK_QUEUE 1
#endif
#ifndef CHECK_GRAPH
#define CHECK_GRAPH 1
#endif

#if CHECK_QUEUE

static volatile int queueCallbacks = 0;
static volatile int queueRunning = -1;

static void refillCallback(void* user, AudioQueueRef queue, AudioQueueBufferRef buffer) {
	memset(buffer->mAudioData, 0, buffer->mAudioDataBytesCapacity);
	buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
	queueCallbacks++;
	AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

static void oneShotCallback(void* user, AudioQueueRef queue, AudioQueueBufferRef buffer) {
	queueCallbacks++;
}

static void runningChanged(void* user, AudioQueueRef queue, AudioQueuePropertyID property) {
	UInt32 running = 0, size = sizeof(running);
	AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size);
	queueRunning = (int) running;
}

static void waitFor(volatile int* value, int atLeast) {
	int i;
	for (i = 0; i < 20 && *value < atLeast; i++)
		usleep(100000);
}

static AudioQueueRef newQueue(const AudioStreamBasicDescription* format, AudioQueueOutputCallback callback,
	const char* what) {
	AudioQueueRef queue = NULL;
	int i;

	queueCallbacks = 0;
	queueRunning = -1;
	expectNoErr(AudioQueueNewOutput(format, callback, NULL, NULL, kCFRunLoopCommonModes, 0, &queue), what);
	if (queue == NULL)
		return NULL;
	AudioQueueAddPropertyListener(queue, kAudioQueueProperty_IsRunning, runningChanged, NULL);

	for (i = 0; i < 3; i++) {
		AudioQueueBufferRef buffer = NULL;
		if (AudioQueueAllocateBuffer(queue, 4096, &buffer) != noErr)
			break;
		memset(buffer->mAudioData, 0, 4096);
		buffer->mAudioDataByteSize = 4096;
		AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
	}
	expect(i == 3, "three buffers allocated and enqueued");
	return queue;
}

static void checkAudioQueue(void) {
	AudioStreamBasicDescription format = int16(44100, 2), readFormat;
	AudioQueueParameterValue volume = 0;
	UInt32 size = sizeof(readFormat);
	AudioQueueRef queue = newQueue(&format, refillCallback, "AudioQueueNewOutput(int16 stereo)");

	if (queue == NULL)
		return;
	expectNoErr(AudioQueueGetProperty(queue, kAudioQueueProperty_StreamDescription, &readFormat, &size), "get the queue's format");
	expect(readFormat.mSampleRate == 44100 && readFormat.mChannelsPerFrame == 2, "the queue reports its format");
	expectNoErr(AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0.5f), "set the volume");
	AudioQueueGetParameter(queue, kAudioQueueParam_Volume, &volume);
	expect(volume == 0.5f, "the volume reads back");

	expectNoErr(AudioQueueStart(queue, NULL), "AudioQueueStart");
	// 1024-frame buffers come back about 43 times a second
	waitFor(&queueCallbacks, 10);
	printf("  %d queue callbacks\n", queueCallbacks);
	expect(queueCallbacks >= 10, "the queue keeps asking for more audio");
	expect(queueRunning == 1, "the IsRunning listener saw the queue start");

	expectNoErr(AudioQueueStop(queue, true), "AudioQueueStop");
	expect(queueRunning == 0, "the IsRunning listener saw the queue stop");
	expectNoErr(AudioQueueDispose(queue, true), "AudioQueueDispose");

	// stopping when the queued buffers have played
	queue = newQueue(&format, oneShotCallback, "AudioQueueNewOutput for a deferred stop");
	if (queue != NULL) {
		int i;
		expectNoErr(AudioQueueStart(queue, NULL), "AudioQueueStart");
		expectNoErr(AudioQueueStop(queue, false), "AudioQueueStop(not immediate)");
		for (i = 0; i < 20 && queueRunning != 0; i++)
			usleep(100000);
		printf("  deferred stop: %d callbacks, running %d\n", queueCallbacks, queueRunning);
		expect(queueRunning == 0 && queueCallbacks == 3, "the queue stops once its three buffers have played");
		AudioQueueDispose(queue, true);
	}

	// a format the output unit doesn't take, so it goes through a converter
	AudioStreamBasicDescription doubles = floatStereo(44100);
	doubles.mBitsPerChannel = 64;
	doubles.mBytesPerFrame = doubles.mBytesPerPacket = 16;
	queue = newQueue(&doubles, refillCallback, "AudioQueueNewOutput(64-bit float)");
	if (queue != NULL) {
		expectNoErr(AudioQueueStart(queue, NULL), "AudioQueueStart(64-bit float)");
		waitFor(&queueCallbacks, 10);
		printf("  %d converted queue callbacks\n", queueCallbacks);
		expect(queueCallbacks >= 10, "a converted queue keeps asking for more audio");
		AudioQueueStop(queue, true);
		AudioQueueDispose(queue, true);
	}
}

#endif

// ---------------------------------------------------------------- AudioUnit and AUGraph

static volatile int renderCallbacks = 0;

static OSStatus renderSilence(void* user, AudioUnitRenderActionFlags* flags, const AudioTimeStamp* time,
	UInt32 bus, UInt32 frames, AudioBufferList* data) {
	UInt32 i;

	for (i = 0; i < data->mNumberBuffers; i++)
		memset(data->mBuffers[i].mData, 0, data->mBuffers[i].mDataByteSize);
	*flags |= kAudioUnitRenderAction_OutputIsSilence;
	renderCallbacks++;
	return noErr;
}

static void checkOutputUnit(void) {
	AudioComponentDescription description = {
		kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0
	};
	AudioComponent component = AudioComponentFindNext(NULL, &description);
	AudioUnit unit = NULL;
	AudioStreamBasicDescription format = floatStereo(44100);
	AURenderCallbackStruct callback = { renderSilence, NULL };
	int i;

	if (component == NULL)
		return;

	expectNoErr(AudioComponentInstanceNew(component, &unit), "AudioComponentInstanceNew(default output)");
	if (unit == NULL)
		return;
	expectNoErr(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)),
		"set the output unit's input format");
	expectNoErr(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)),
		"set the render callback");
	expectNoErr(AudioUnitInitialize(unit), "AudioUnitInitialize");

	renderCallbacks = 0;
	expectNoErr(AudioOutputUnitStart(unit), "AudioOutputUnitStart");
	for (i = 0; i < 10 && renderCallbacks < 5; i++)
		usleep(100000);
	printf("  %d render callbacks\n", renderCallbacks);
	expect(renderCallbacks >= 2, "the output unit pulls audio");
	expectNoErr(AudioOutputUnitStop(unit), "AudioOutputUnitStop");

	AudioUnitUninitialize(unit);
	AudioComponentInstanceDispose(unit);
}

#if CHECK_GRAPH
static void checkGraph(void) {
	AUGraph graph = NULL;
	AUNode output;
	AudioComponentDescription description = {
		kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0
	};
	AURenderCallbackStruct callback = { renderSilence, NULL };
	Boolean running = false;
	int i;

	expectNoErr(NewAUGraph(&graph), "NewAUGraph");
	if (graph == NULL)
		return;
	expectNoErr(AUGraphAddNode(graph, &description, &output), "AUGraphAddNode(default output)");
	expectNoErr(AUGraphOpen(graph), "AUGraphOpen");
	expectNoErr(AUGraphSetNodeInputCallback(graph, output, 0, &callback), "AUGraphSetNodeInputCallback");
	expectNoErr(AUGraphInitialize(graph), "AUGraphInitialize");

	renderCallbacks = 0;
	expectNoErr(AUGraphStart(graph), "AUGraphStart");
	AUGraphIsRunning(graph, &running);
	expect(running, "the graph says it runs");
	for (i = 0; i < 10 && renderCallbacks < 5; i++)
		usleep(100000);
	printf("  %d graph render callbacks\n", renderCallbacks);
	expect(renderCallbacks >= 2, "the graph pulls audio from the node's input callback");
	expectNoErr(AUGraphStop(graph), "AUGraphStop");
	AUGraphUninitialize(graph);
	AUGraphClose(graph);
	DisposeAUGraph(graph);
}

#endif

// ---------------------------------------------------------------- AudioConverter

typedef struct {
	float* samples;
	UInt32 frames;
	UInt32 position;
} SineSource;

static OSStatus provideSine(AudioConverterRef converter, UInt32* packets, AudioBufferList* data,
	AudioStreamPacketDescription** descriptions, void* user) {
	SineSource* source = (SineSource*) user;
	UInt32 left = source->frames - source->position;

	if (*packets > left)
		*packets = left;
	data->mNumberBuffers = 1;
	data->mBuffers[0].mNumberChannels = 1;
	data->mBuffers[0].mData = source->samples + source->position;
	data->mBuffers[0].mDataByteSize = *packets * sizeof(float);
	source->position += *packets;
	return noErr;
}

static void checkConverter(void) {
	AudioStreamBasicDescription from, to = int16(44100, 1);
	AudioConverterRef converter = NULL;
	SineSource source;
	UInt32 i;

	memset(&from, 0, sizeof(from));
	from.mSampleRate = 48000;
	from.mFormatID = kAudioFormatLinearPCM;
	from.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	from.mChannelsPerFrame = 1;
	from.mBitsPerChannel = 32;
	from.mFramesPerPacket = 1;
	from.mBytesPerFrame = 4;
	from.mBytesPerPacket = 4;

	expectNoErr(AudioConverterNew(&from, &to, &converter), "AudioConverterNew(48 kHz float -> 44.1 kHz int16)");
	if (converter == NULL)
		return;

	// one second of a 440 Hz tone at half scale
	source.frames = 48000;
	source.position = 0;
	source.samples = malloc(sizeof(float) * source.frames);
	for (i = 0; i < source.frames; i++)
		source.samples[i] = 0.5f * sinf(2 * M_PI * 440 * i / 48000.0f);

	int16_t* output = malloc(sizeof(int16_t) * 50000);
	UInt32 total = 0;
	OSStatus status = noErr;
	while (status == noErr && total < 50000) {
		AudioBufferList list;
		UInt32 frames = 4096;

		if (total + frames > 50000)
			frames = 50000 - total;
		list.mNumberBuffers = 1;
		list.mBuffers[0].mNumberChannels = 1;
		list.mBuffers[0].mData = output + total;
		list.mBuffers[0].mDataByteSize = frames * sizeof(int16_t);
		status = AudioConverterFillComplexBuffer(converter, provideSine, &source, &frames, &list, NULL);
		total += frames;
		if (frames == 0)
			break;
	}

	int16_t peak = 0;
	for (i = 0; i < total; i++)
		if (abs(output[i]) > peak)
			peak = (int16_t) abs(output[i]);
	printf("  converted %u frames (status %d), peak %d\n", (unsigned) total, (int) status, peak);
	expect(total > 43500 && total < 44700, "about a second of output at 44.1 kHz");
	expect(peak > 14000 && peak < 18000, "the tone keeps its level (half scale is 16384)");

	free(output);
	free(source.samples);
	AudioConverterDispose(converter);
}

// ---------------------------------------------------------------- AudioFile / ExtAudioFile

static void checkFiles(void) {
	AudioStreamBasicDescription format = int16(22050, 1);
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, CFSTR("/tmp/coreaudio-basics.wav"), kCFURLPOSIXPathStyle, false);
	AudioFileID file = NULL;
	int16_t samples[2205];
	UInt32 i;

	for (i = 0; i < 2205; i++)
		samples[i] = (int16_t) (8000 * sin(2 * M_PI * 1000 * i / 22050.0));

	expectNoErr(AudioFileCreateWithURL(url, kAudioFileWAVEType, &format, kAudioFileFlags_EraseFile, &file),
		"AudioFileCreateWithURL(WAV)");
	if (file != NULL) {
		UInt32 bytes = sizeof(samples);
		expectNoErr(AudioFileWriteBytes(file, false, 0, &bytes, samples), "AudioFileWriteBytes");
		expectNoErr(AudioFileClose(file), "AudioFileClose after writing");
		file = NULL;
	}

	expectNoErr(AudioFileOpenURL(url, kAudioFileReadPermission, 0, &file), "AudioFileOpenURL");
	if (file != NULL) {
		AudioStreamBasicDescription read;
		UInt32 size = sizeof(read);
		UInt64 packets = 0;

		AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &read);
		size = sizeof(packets);
		AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &size, &packets);
		printf("  read back: %.0f Hz, %u channels, %u bits, %llu packets\n", read.mSampleRate,
			(unsigned) read.mChannelsPerFrame, (unsigned) read.mBitsPerChannel, (unsigned long long) packets);
		expect(read.mSampleRate == 22050 && read.mChannelsPerFrame == 1 && read.mBitsPerChannel == 16 && packets == 2205,
			"the WAV file reads back with its format and length");
		AudioFileClose(file);
	}

	ExtAudioFileRef ext = NULL;
	expectNoErr(ExtAudioFileOpenURL(url, &ext), "ExtAudioFileOpenURL");
	if (ext != NULL) {
		AudioStreamBasicDescription client = floatStereo(44100);
		float* buffer = malloc(sizeof(float) * 2 * 6000);
		AudioBufferList list;
		UInt32 frames = 6000;

		expectNoErr(ExtAudioFileSetProperty(ext, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client),
			"ExtAudioFile client format (44.1 kHz float stereo)");
		list.mNumberBuffers = 1;
		list.mBuffers[0].mNumberChannels = 2;
		list.mBuffers[0].mData = buffer;
		list.mBuffers[0].mDataByteSize = sizeof(float) * 2 * 6000;
		expectNoErr(ExtAudioFileRead(ext, &frames, &list), "ExtAudioFileRead");
		printf("  ExtAudioFile gave %u frames\n", (unsigned) frames);
		expect(frames > 4000 && frames <= 4410, "the 0.1 s file converts to about 4410 frames");
		free(buffer);
		ExtAudioFileDispose(ext);
	}

	CFRelease(url);
	unlink("/tmp/coreaudio-basics.wav");
}

int main(int argc, char** argv) {
	// keep what was printed if something crashes
	setvbuf(stdout, NULL, _IONBF, 0);
	checkDevice();
#if CHECK_QUEUE
	checkAudioQueue();
#endif
	checkOutputUnit();
#if CHECK_GRAPH
	checkGraph();
#endif
	checkConverter();
	checkFiles();

	printf("%s (%d failures)\n", failures ? "FAILED" : "ALL PASSED", failures);
	return failures ? 1 : 0;
}
