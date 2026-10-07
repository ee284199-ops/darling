#ifndef AUDIOQUEUEBASE_H
#define	AUDIOQUEUEBASE_H
#include "AudioQueue.h"
#include <mutex>
#include <vector>

class AudioQueue
{
public:
	AudioQueue(const AudioStreamBasicDescription* format, void* userData,
			CFRunLoopRef runloop, CFStringRef runloopMode, UInt32 flags);
	virtual ~AudioQueue();
	
	virtual OSStatus start(const AudioTimeStamp *inStartTime) = 0;
	virtual OSStatus prime(UInt32 inNumberOfFramesToPrepare, UInt32 *outNumberOfFramesPrepared) = 0;
	virtual OSStatus flush() = 0;
	virtual OSStatus stop(Boolean inImmediate) = 0;
	virtual OSStatus pause() = 0;
	virtual OSStatus reset() = 0;

	virtual OSStatus dispose(Boolean inImmediate) = 0;

	virtual OSStatus getParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue *outValue);
	virtual OSStatus setParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue inValue);

	virtual OSStatus getProperty(AudioQueuePropertyID inID, void *outData, UInt32 *ioDataSize);
	virtual OSStatus setProperty(AudioQueuePropertyID inID, const void *inData, UInt32 inDataSize);
	virtual OSStatus getPropertySize(AudioQueuePropertyID inID, UInt32 *outDataSize);

	OSStatus addPropertyListener(AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData);
	OSStatus removePropertyListener(AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData);

	virtual OSStatus setOfflineRenderFormat(const AudioStreamBasicDescription *inFormat, const AudioChannelLayout *inLayout) = 0;
	virtual OSStatus offlineRender(const AudioTimeStamp *inTimestamp, AudioQueueBufferRef ioBuffer, UInt32 inNumberFrames) = 0;

	virtual OSStatus allocateBuffer(UInt32 inBufferByteSize, AudioQueueBufferRef *outBuffer);
	virtual OSStatus allocateBufferWithPacketDescriptions(UInt32 inBufferByteSize, UInt32 inNumberPacketDescriptions, AudioQueueBufferRef *outBuffer);
	virtual OSStatus freeBuffer(AudioQueueBufferRef inBuffer);
	virtual OSStatus enqueueBuffer(AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription *inPacketDescs);
	virtual OSStatus getCurrentTime(AudioQueueTimelineRef inTimeline, AudioTimeStamp *outTimeStamp, Boolean *outTimelineDiscontinuity);

protected:
	bool isRunning();
	void setRunning(bool running);
	void notifyPropertyListeners(AudioQueuePropertyID inID);

	struct PropertyListener
	{
		AudioQueuePropertyID property;
		AudioQueuePropertyListenerProc proc;
		void* userData;
	};

	AudioStreamBasicDescription m_format;
	void* m_userData;
	CFRunLoopRef m_runloop;
	CFStringRef m_runloopMode;
	UInt32 m_flags;

	std::mutex m_listenersMutex;
	std::vector<PropertyListener> m_listeners;
	bool m_isRunning;

private:
	std::mutex m_buffersMutex;
	std::vector<AudioQueueBufferRef> m_buffers;
};

#endif	/* AUDIOQUEUEBASE_H */

