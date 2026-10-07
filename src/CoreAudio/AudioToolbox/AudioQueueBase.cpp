#include "AudioQueueBase.h"
#include "stub.h"
#include <CarbonCore/MacErrors.h>
#include <new>
#include <stdlib.h>

AudioQueue::AudioQueue(const AudioStreamBasicDescription* format, void* userData,
			CFRunLoopRef runloop, CFStringRef runloopMode, UInt32 flags)
: m_format(*format), m_userData(userData), m_flags(flags), m_isRunning(false)
{
	// both may be NULL: callbacks then run on an internal thread, in the common modes
	m_runloop = runloop ? (CFRunLoopRef) CFRetain(runloop) : nullptr;
	m_runloopMode = runloopMode ? (CFStringRef) CFRetain(runloopMode) : nullptr;
}

AudioQueue::~AudioQueue()
{
	for (AudioQueueBufferRef buffer : m_buffers)
	{
		free(buffer->mAudioData);
		free(buffer->mPacketDescriptions);
		free(buffer);
	}
	if (m_runloop)
		CFRelease(m_runloop);
	if (m_runloopMode)
		CFRelease(m_runloopMode);
}

OSStatus AudioQueue::getParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue *outValue)
{
	(void) inParamID;
	(void) outValue;
	STUB();
	return unimpErr;
}

OSStatus AudioQueue::setParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue inValue)
{
	(void) inParamID;
	(void) inValue;
	STUB();
	return unimpErr;
}

OSStatus AudioQueue::getProperty(AudioQueuePropertyID inID, void *outData, UInt32 *ioDataSize)
{
	switch (inID)
	{
		case kAudioQueueProperty_IsRunning:
		{
			if (outData == nullptr || ioDataSize == nullptr)
				return kAudio_ParamError;
			if (*ioDataSize < sizeof(UInt32))
				return kAudioQueueErr_InvalidPropertySize;
			{
				std::lock_guard<std::mutex> lock(m_listenersMutex);
				*(UInt32*) outData = m_isRunning ? 1 : 0;
			}
			*ioDataSize = sizeof(UInt32);
			return noErr;
		}
	}
	STUB();
	return kAudioQueueErr_InvalidProperty;
}

OSStatus AudioQueue::setProperty(AudioQueuePropertyID inID, const void *inData, UInt32 inDataSize)
{
	(void) inData;
	(void) inDataSize;
	STUB();
	return kAudioQueueErr_InvalidProperty;
}

OSStatus AudioQueue::getPropertySize(AudioQueuePropertyID inID, UInt32 *outDataSize)
{
	switch (inID)
	{
		case kAudioQueueProperty_IsRunning:
		{
			if (outDataSize == nullptr)
				return kAudio_ParamError;
			*outDataSize = sizeof(UInt32);
			return noErr;
		}
	}
	STUB();
	return kAudioQueueErr_InvalidProperty;
}

OSStatus AudioQueue::addPropertyListener(AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData)
{
	if (inProc == nullptr)
		return kAudio_ParamError;

	std::lock_guard<std::mutex> lock(m_listenersMutex);
	PropertyListener listener;
	listener.property = inID;
	listener.proc = inProc;
	listener.userData = inUserData;
	m_listeners.push_back(listener);
	return noErr;
}

OSStatus AudioQueue::removePropertyListener(AudioQueuePropertyID inID, AudioQueuePropertyListenerProc inProc, void *inUserData)
{
	if (inProc == nullptr)
		return kAudio_ParamError;

	std::lock_guard<std::mutex> lock(m_listenersMutex);
	for (auto it = m_listeners.begin(); it != m_listeners.end();)
	{
		if (it->property == inID && it->proc == inProc && it->userData == inUserData)
			it = m_listeners.erase(it);
		else
			++it;
	}
	return noErr;
}

bool AudioQueue::isRunning()
{
	std::lock_guard<std::mutex> lock(m_listenersMutex);
	return m_isRunning;
}

void AudioQueue::setRunning(bool running)
{
	{
		std::lock_guard<std::mutex> lock(m_listenersMutex);
		if (m_isRunning == running)
			return;
		m_isRunning = running;
	}
	notifyPropertyListeners(kAudioQueueProperty_IsRunning);
}

void AudioQueue::notifyPropertyListeners(AudioQueuePropertyID inID)
{
	std::vector<PropertyListener> listeners;
	{
		std::lock_guard<std::mutex> lock(m_listenersMutex);
		for (PropertyListener& listener : m_listeners)
		{
			if (listener.property == inID)
				listeners.push_back(listener);
		}
	}
	for (PropertyListener& listener : listeners)
		listener.proc(listener.userData, this, inID);
}

OSStatus AudioQueue::allocateBuffer(UInt32 inBufferByteSize, AudioQueueBufferRef *outBuffer)
{
	return allocateBufferWithPacketDescriptions(inBufferByteSize, 0, outBuffer);
}

OSStatus AudioQueue::allocateBufferWithPacketDescriptions(UInt32 inBufferByteSize, UInt32 inNumberPacketDescriptions, AudioQueueBufferRef *outBuffer)
{
	if (outBuffer == nullptr)
		return kAudio_ParamError;
	*outBuffer = nullptr;

	void* data = calloc(1, inBufferByteSize);
	if (data == nullptr)
		return kAudio_MemFullError;

	AudioStreamPacketDescription* packetDescriptions = nullptr;
	if (inNumberPacketDescriptions > 0)
	{
		packetDescriptions = (AudioStreamPacketDescription*) calloc(inNumberPacketDescriptions,
				sizeof(AudioStreamPacketDescription));
		if (packetDescriptions == nullptr)
		{
			free(data);
			return kAudio_MemFullError;
		}
	}

	AudioQueueBufferRef buffer = (AudioQueueBufferRef) malloc(sizeof(AudioQueueBuffer));
	if (buffer == nullptr)
	{
		free(packetDescriptions);
		free(data);
		return kAudio_MemFullError;
	}

	new (buffer) AudioQueueBuffer{inBufferByteSize, data, 0, nullptr,
			inNumberPacketDescriptions, packetDescriptions, 0};

	{
		std::lock_guard<std::mutex> lock(m_buffersMutex);
		m_buffers.push_back(buffer);
	}
	*outBuffer = buffer;
	return noErr;
}

OSStatus AudioQueue::freeBuffer(AudioQueueBufferRef inBuffer)
{
	if (inBuffer == nullptr)
		return kAudio_ParamError;

	{
		std::lock_guard<std::mutex> lock(m_buffersMutex);
		for (auto it = m_buffers.begin(); it != m_buffers.end(); ++it)
		{
			if (*it == inBuffer)
			{
				m_buffers.erase(it);
				break;
			}
		}
	}
	free(inBuffer->mAudioData);
	free(inBuffer->mPacketDescriptions);
	free(inBuffer);
	return noErr;
}

OSStatus AudioQueue::enqueueBuffer(AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription *inPacketDescs)
{
	(void) inBuffer;
	(void) inNumPacketDescs;
	(void) inPacketDescs;
	STUB();
	return unimpErr;
}

OSStatus AudioQueue::getCurrentTime(AudioQueueTimelineRef inTimeline, AudioTimeStamp *outTimeStamp, Boolean *outTimelineDiscontinuity)
{
	(void) inTimeline;
	(void) outTimeStamp;
	(void) outTimelineDiscontinuity;
	STUB();
	return unimpErr;
}
