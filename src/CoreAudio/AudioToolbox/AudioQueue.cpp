#include "AudioQueue.h"
#include "AudioQueueOutput.h"
#include <CarbonCore/MacErrors.h>
#include <mach/mach_time.h>
#include <string.h>

OSStatus AudioQueueStart(AudioQueueRef inAQ, const AudioTimeStamp *inStartTime)
{
	return inAQ->start(inStartTime);
}

OSStatus AudioQueuePrime(AudioQueueRef inAQ, UInt32 inNumberOfFramesToPrepare, UInt32 *outNumberOfFramesPrepared)
{
	return inAQ->prime(inNumberOfFramesToPrepare, outNumberOfFramesPrepared);
}

OSStatus AudioQueueFlush(AudioQueueRef inAQ)
{
	return inAQ->flush();
}

OSStatus AudioQueueStop(AudioQueueRef inAQ, Boolean inImmediate)
{
	return inAQ->stop(inImmediate);
}

OSStatus AudioQueuePause(AudioQueueRef inAQ)
{
	return inAQ->pause();
}

OSStatus AudioQueueReset(AudioQueueRef inAQ)
{
	return inAQ->reset();
}

OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *inFormat,
		AudioQueueOutputCallback inCallbackProc,
		void *inUserData, CFRunLoopRef inCallbackRunLoop,
		CFStringRef inCallbackRunLoopMode, UInt32 inFlags,
		AudioQueueRef *outAQ)
{
	return AudioQueueOutput::create(inFormat, inCallbackProc, inUserData,
			inCallbackRunLoop, inCallbackRunLoopMode, inFlags,
			(AudioQueueOutput**) outAQ);
}

OSStatus AudioQueueNewInput(const AudioStreamBasicDescription *inFormat,
		AudioQueueInputCallback inCallbackProc,
		void *inUserData, CFRunLoopRef inCallbackRunLoop,
		CFStringRef inCallbackRunLoopMode, UInt32 inFlags,
		AudioQueueRef *outAQ)
{
	*outAQ = nullptr;
	return unimpErr;
}

OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef *outAQ,
		const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
		dispatch_queue_t inCallbackDispatchQueue, AudioQueueOutputCallbackBlock inCallbackBlock)
{
	return AudioQueueOutput::create(inFormat, inFlags, inCallbackDispatchQueue, inCallbackBlock,
			(AudioQueueOutput**) outAQ);
}

OSStatus AudioQueueNewInputWithDispatchQueue(AudioQueueRef *outAQ,
		const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
		dispatch_queue_t inCallbackDispatchQueue, AudioQueueInputCallbackBlock inCallbackBlock)
{
	if (outAQ)
		*outAQ = nullptr;
	return unimpErr;
}

OSStatus AudioQueueDispose(AudioQueueRef inAQ, Boolean inImmediate)
{
	return inAQ->dispose(inImmediate);
}

OSStatus AudioQueueGetParameter(AudioQueueRef inAQ, AudioQueueParameterID inParamID, AudioQueueParameterValue *outValue)
{
	return inAQ->getParameter(inParamID, outValue);
}

OSStatus AudioQueueSetParameter(AudioQueueRef inAQ, AudioQueueParameterID inParamID, AudioQueueParameterValue inValue)
{
	return inAQ->setParameter(inParamID, inValue);
}
 
OSStatus AudioQueueGetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, void *outData, UInt32 *ioDataSize)
{
	return inAQ->getProperty(inID, outData, ioDataSize);
}

OSStatus AudioQueueSetProperty(AudioQueueRef inAQ, AudioQueuePropertyID inID, const void *inData, UInt32 inDataSize)
{
	return inAQ->setProperty(inID, inData, inDataSize);
}

OSStatus AudioQueueGetPropertySize(AudioQueueRef inAQ, AudioQueuePropertyID inID, UInt32 *outDataSize)
{
	return inAQ->getPropertySize(inID, outDataSize);
}

OSStatus AudioQueueAddPropertyListener(AudioQueueRef inAQ, AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData)
{
	return inAQ->addPropertyListener(inID, inProc, inUserData);
}

OSStatus AudioQueueRemovePropertyListener(AudioQueueRef inAQ, AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData)
{
	return inAQ->removePropertyListener(inID, inProc, inUserData);
}

OSStatus AudioQueueSetOfflineRenderFormat(AudioQueueRef inAQ, const AudioStreamBasicDescription *inFormat, const AudioChannelLayout *inLayout)
{
	return inAQ->setOfflineRenderFormat(inFormat, inLayout);
}

OSStatus AudioQueueOfflineRender(AudioQueueRef inAQ, const AudioTimeStamp *inTimestamp, AudioQueueBufferRef ioBuffer, UInt32 inNumberFrames)
{
	return inAQ->offlineRender(inTimestamp, ioBuffer, inNumberFrames);
}

OSStatus AudioQueueAllocateBuffer(AudioQueueRef inAQ, UInt32 inBufferByteSize, AudioQueueBufferRef *outBuffer)
{
	if (inAQ == nullptr || outBuffer == nullptr)
		return kAudio_ParamError;
	return inAQ->allocateBuffer(inBufferByteSize, outBuffer);
}

OSStatus AudioQueueAllocateBufferWithPacketDescriptions(AudioQueueRef inAQ,
		UInt32 inBufferByteSize, UInt32 inNumberPacketDescriptions,
		AudioQueueBufferRef *outBuffer)
{
	if (inAQ == nullptr || outBuffer == nullptr)
		return kAudio_ParamError;
	return inAQ->allocateBufferWithPacketDescriptions(inBufferByteSize,
			inNumberPacketDescriptions, outBuffer);
}

OSStatus AudioQueueFreeBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
	if (inAQ == nullptr || inBuffer == nullptr)
		return kAudio_ParamError;
	return inAQ->freeBuffer(inBuffer);
}

OSStatus AudioQueueEnqueueBuffer(AudioQueueRef inAQ, AudioQueueBufferRef inBuffer,
		UInt32 inNumPacketDescs, const AudioStreamPacketDescription *inPacketDescs)
{
	if (inAQ == nullptr || inBuffer == nullptr)
		return kAudio_ParamError;
	return inAQ->enqueueBuffer(inBuffer, inNumPacketDescs, inPacketDescs);
}

OSStatus AudioQueueEnqueueBufferWithParameters(AudioQueueRef inAQ,
		AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs,
		const AudioStreamPacketDescription *inPacketDescs,
		UInt32 inTrimFramesAtStart, UInt32 inTrimFramesAtEnd,
		UInt32 inNumParamValues, const AudioQueueParameterEvent *inParamValues,
		const AudioTimeStamp *inStartTime, AudioTimeStamp *outActualStartTime)
{
	(void) inTrimFramesAtStart;
	(void) inTrimFramesAtEnd;
	(void) inNumParamValues;
	(void) inParamValues;
	(void) inStartTime;
	(void) outActualStartTime;
	if (inAQ == nullptr || inBuffer == nullptr)
		return kAudio_ParamError;
	return inAQ->enqueueBuffer(inBuffer, inNumPacketDescs, inPacketDescs);
}

OSStatus AudioQueueGetCurrentTime(AudioQueueRef inAQ, AudioQueueTimelineRef inTimeline,
		AudioTimeStamp *outTimeStamp, Boolean *outTimelineDiscontinuity)
{
	if (inAQ == nullptr)
		return kAudio_ParamError;
	return inAQ->getCurrentTime(inTimeline, outTimeStamp, outTimelineDiscontinuity);
}

// Our queues play continuously, so a timeline never reports a discontinuity; any non-NULL value does
OSStatus AudioQueueCreateTimeline(AudioQueueRef inAQ, AudioQueueTimelineRef *outTimeline)
{
	if (inAQ == nullptr || outTimeline == nullptr)
		return kAudio_ParamError;
	*outTimeline = reinterpret_cast<AudioQueueTimelineRef>(inAQ);
	return noErr;
}

OSStatus AudioQueueDisposeTimeline(AudioQueueRef inAQ, AudioQueueTimelineRef inTimeline)
{
	return (inAQ == nullptr) ? kAudio_ParamError : noErr;
}

OSStatus AudioQueueDeviceGetCurrentTime(AudioQueueRef inAQ, AudioTimeStamp *outTimeStamp)
{
	if (inAQ == nullptr || outTimeStamp == nullptr)
		return kAudio_ParamError;

	OSStatus status = inAQ->getCurrentTime(nullptr, outTimeStamp, nullptr);
	if (status != noErr)
		memset(outTimeStamp, 0, sizeof(*outTimeStamp));
	outTimeStamp->mHostTime = mach_absolute_time();
	outTimeStamp->mFlags |= kAudioTimeStampHostTimeValid;
	return noErr;
}

OSStatus AudioQueueDeviceGetNearestStartTime(AudioQueueRef inAQ, AudioTimeStamp *ioRequestedStartTime, UInt32 inFlags)
{
	// any time will do
	return (inAQ == nullptr || ioRequestedStartTime == nullptr) ? kAudio_ParamError : noErr;
}

OSStatus AudioQueueDeviceTranslateTime(AudioQueueRef inAQ, const AudioTimeStamp *inTime, AudioTimeStamp *outTime)
{
	if (inAQ == nullptr || inTime == nullptr || outTime == nullptr)
		return kAudio_ParamError;
	*outTime = *inTime;
	return noErr;
}
