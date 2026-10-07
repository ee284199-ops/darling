#include "AudioQueueOutput.h"
#include "stub.h"
#include <AudioToolbox/AudioComponent.h>
#include <AudioToolbox/AudioFormat.h>
#include <AudioToolbox/AudioOutputUnit.h>
#include <AudioToolbox/AudioUnitProperties.h>
#include <CarbonCore/MacErrors.h>
#include <Block.h>
#include <algorithm>
#include <cmath>
#include <string.h>

static const UInt32 kMaxMeteredChannels = 16;

AudioQueueOutput::AudioQueueOutput(const AudioStreamBasicDescription *inFormat,
		AudioQueueOutputCallback inCallbackProc,
	void *inUserData, CFRunLoopRef inCallbackRunLoop,
	CFStringRef inCallbackRunLoopMode, UInt32 inFlags)
: AudioQueue(inFormat, inUserData, inCallbackRunLoop, inCallbackRunLoopMode, inFlags),
		m_callback(inCallbackProc), m_callbackState(std::make_shared<CallbackState>()),
		m_volume(1.0f), m_framesRendered(0), m_metering(false)
{
	memset(&m_unitFormat, 0, sizeof(m_unitFormat));
	if (m_runloop == nullptr)
		m_callbackQueue = dispatch_queue_create("org.darlinghq.audiotoolbox.audioqueue", nullptr);
}

AudioQueueOutput::AudioQueueOutput(const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
		dispatch_queue_t inCallbackQueue, AudioQueueOutputCallbackBlock inCallbackBlock)
: AudioQueue(inFormat, nullptr, nullptr, nullptr, inFlags),
		m_callbackBlock(Block_copy(inCallbackBlock)), m_callbackQueue(inCallbackQueue),
		m_callbackState(std::make_shared<CallbackState>()),
		m_volume(1.0f), m_framesRendered(0), m_metering(false)
{
	memset(&m_unitFormat, 0, sizeof(m_unitFormat));
	dispatch_retain(m_callbackQueue);
}

AudioQueueOutput::~AudioQueueOutput()
{
	if (m_outputUnit != nullptr)
	{
		AudioUnitUninitialize(m_outputUnit);
		AudioComponentInstanceDispose(m_outputUnit);
	}
	if (m_converter != nullptr)
		AudioConverterDispose(m_converter);
	if (m_callbackQueue != nullptr)
		dispatch_release(m_callbackQueue);
	if (m_callbackBlock != nullptr)
		Block_release(m_callbackBlock);
	if (m_currentDevice != nullptr)
		CFRelease(m_currentDevice);
}

// Rejects formats that can't be played at all, which Apple does when the queue is created
OSStatus AudioQueueOutput::checkFormat()
{
	if (m_format.mSampleRate <= 0 || m_format.mChannelsPerFrame == 0)
		return kAudioFormatUnsupportedDataFormatError;
	if (m_format.mFormatID == kAudioFormatLinearPCM && (m_format.mBytesPerFrame == 0 || m_format.mBitsPerChannel == 0))
		return kAudioFormatUnsupportedDataFormatError;
	return noErr;
}

OSStatus AudioQueueOutput::createOutputUnit()
{
	AudioComponentDescription desc;
	memset(&desc, 0, sizeof(desc));
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_DefaultOutput;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;

	AudioComponent component = AudioComponentFindNext(nullptr, &desc);
	if (component == nullptr)
		return kAudioQueueErr_InvalidDevice;

	OSStatus status = AudioComponentInstanceNew(component, &m_outputUnit);
	if (status != noErr)
	{
		m_outputUnit = nullptr;
		return status;
	}

	// The unit plays linear PCM as is. Anything else gets decoded/converted to floats.
	m_unitFormat = m_format;
	status = AudioUnitSetProperty(m_outputUnit, kAudioUnitProperty_StreamFormat,
			kAudioUnitScope_Input, 0, &m_format, sizeof(m_format));
	if (status != noErr)
	{
		memset(&m_unitFormat, 0, sizeof(m_unitFormat));
		m_unitFormat.mSampleRate = m_format.mSampleRate;
		m_unitFormat.mFormatID = kAudioFormatLinearPCM;
		m_unitFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
		m_unitFormat.mChannelsPerFrame = m_format.mChannelsPerFrame;
		m_unitFormat.mFramesPerPacket = 1;
		m_unitFormat.mBitsPerChannel = 32;
		m_unitFormat.mBytesPerFrame = m_unitFormat.mBytesPerPacket = 4 * m_format.mChannelsPerFrame;

		status = AudioUnitSetProperty(m_outputUnit, kAudioUnitProperty_StreamFormat,
				kAudioUnitScope_Input, 0, &m_unitFormat, sizeof(m_unitFormat));
		if (status == noErr)
			status = createConverter();
	}

	if (status == noErr)
	{
		AURenderCallbackStruct callback;
		memset(&callback, 0, sizeof(callback));
		callback.inputProc = renderStatic;
		callback.inputProcRefCon = this;
		status = AudioUnitSetProperty(m_outputUnit, kAudioUnitProperty_SetRenderCallback,
				kAudioUnitScope_Input, 0, &callback, sizeof(callback));
	}
	if (status == noErr)
		status = AudioUnitInitialize(m_outputUnit);

	if (status != noErr)
	{
		if (m_converter != nullptr)
		{
			AudioConverterDispose(m_converter);
			m_converter = nullptr;
		}
		AudioComponentInstanceDispose(m_outputUnit);
		m_outputUnit = nullptr;
	}
	return status;
}

OSStatus AudioQueueOutput::createConverter()
{
	OSStatus status = AudioConverterNew(&m_format, &m_unitFormat, &m_converter);
	if (status != noErr)
	{
		m_converter = nullptr;
		return status;
	}

	std::lock_guard<std::mutex> lock(m_queueMutex);
	if (!m_magicCookie.empty())
	{
		AudioConverterSetProperty(m_converter, kAudioConverterDecompressionMagicCookie,
				UInt32(m_magicCookie.size()), m_magicCookie.data());
	}
	return noErr;
}

OSStatus AudioQueueOutput::start(const AudioTimeStamp *inStartTime)
{
	(void) inStartTime;

	{
		std::lock_guard<std::mutex> lock(m_stateMutex);
		if (isRunning())
			return noErr;
		if (m_outputUnit == nullptr)
		{
			OSStatus status = createOutputUnit();
			if (status != noErr)
				return status;
		}
		{
			std::lock_guard<std::mutex> queueLock(m_queueMutex);
			m_stopping = false;
		}
		OSStatus status = AudioOutputUnitStart(m_outputUnit);
		if (status != noErr)
			return status;
	}
	setRunning(true);
	return noErr;
}

OSStatus AudioQueueOutput::prime(UInt32 inNumberOfFramesToPrepare, UInt32 *outNumberOfFramesPrepared)
{
	(void) inNumberOfFramesToPrepare;
	if (outNumberOfFramesPrepared != nullptr)
		*outNumberOfFramesPrepared = 0;

	// get ready to start playing
	std::lock_guard<std::mutex> lock(m_stateMutex);
	if (m_outputUnit == nullptr)
		return createOutputUnit();
	return noErr;
}

OSStatus AudioQueueOutput::flush()
{
	return noErr;
}

void AudioQueueOutput::stopUnit()
{
	{
		std::lock_guard<std::mutex> lock(m_stateMutex);
		// once this returns, the unit won't call us for more data
		if (m_outputUnit != nullptr)
			AudioOutputUnitStop(m_outputUnit);
	}
	setRunning(false);
}

OSStatus AudioQueueOutput::pause()
{
	stopUnit();
	return noErr;
}

OSStatus AudioQueueOutput::stop(Boolean inImmediate)
{
	if (!inImmediate)
	{
		// play what's queued first; the render callback stops once it's all gone
		std::lock_guard<std::mutex> lock(m_queueMutex);
		if (isRunning() && !m_pendingBuffers.empty())
		{
			m_stopping = true;
			return noErr;
		}
	}

	stopUnit();
	reset();
	return noErr;
}

// Drops whatever is queued, handing the buffers back to the client
OSStatus AudioQueueOutput::reset()
{
	std::deque<AudioQueueBufferRef> dropped;
	{
		std::lock_guard<std::mutex> renderLock(m_renderMutex);
		std::lock_guard<std::mutex> lock(m_queueMutex);

		if (m_handedOut != nullptr)
		{
			dropped.push_back(m_handedOut);
			m_handedOut = nullptr;
		}
		dropped.insert(dropped.end(), m_pendingBuffers.begin(), m_pendingBuffers.end());
		m_pendingBuffers.clear();
		m_bufferOffset = 0;
		m_stopping = false;

		if (m_converter != nullptr)
			AudioConverterReset(m_converter);
	}
	returnBuffers(dropped);
	return noErr;
}

OSStatus AudioQueueOutput::dispose(Boolean inImmediate)
{
	(void) inImmediate;

	{
		std::lock_guard<std::mutex> lock(m_stateMutex);
		if (m_outputUnit != nullptr)
			AudioOutputUnitStop(m_outputUnit);
	}

	{
		// waits for a callback in progress on another thread (or is that callback)
		std::lock_guard<std::recursive_mutex> lock(m_callbackState->mutex);
		m_callbackState->alive = false;
	}
	delete this;
	return noErr;
}

OSStatus AudioQueueOutput::getParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue *outValue)
{
	if (outValue == nullptr)
		return kAudio_ParamError;
	switch (inParamID)
	{
		case kAudioQueueParam_Volume:
			*outValue = m_volume.load();
			return noErr;
		case kAudioQueueParam_PlayRate:
			*outValue = 1.0f;
			return noErr;
		case kAudioQueueParam_Pitch:
		case kAudioQueueParam_VolumeRampTime:
		case kAudioQueueParam_Pan:
			*outValue = 0.0f;
			return noErr;
	}
	return kAudioQueueErr_InvalidParameter;
}

OSStatus AudioQueueOutput::setParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue inValue)
{
	switch (inParamID)
	{
		case kAudioQueueParam_Volume:
			m_volume.store(std::clamp(inValue, 0.0f, 1.0f));
			return noErr;
		case kAudioQueueParam_PlayRate:
		case kAudioQueueParam_Pitch:
		case kAudioQueueParam_VolumeRampTime:
		case kAudioQueueParam_Pan:
			// accepted, but there's no time/pitch processing or panning
			return noErr;
	}
	return kAudioQueueErr_InvalidParameter;
}

template <typename T>
static OSStatus getValue(const T& value, void* outData, UInt32* ioDataSize)
{
	if (*ioDataSize < sizeof(T))
		return kAudioQueueErr_InvalidPropertySize;
	memcpy(outData, &value, sizeof(T));
	*ioDataSize = sizeof(T);
	return noErr;
}

OSStatus AudioQueueOutput::getPropertySize(AudioQueuePropertyID inID, UInt32 *outDataSize)
{
	if (outDataSize == nullptr)
		return kAudio_ParamError;

	switch (inID)
	{
		case kAudioQueueProperty_StreamDescription:
			*outDataSize = sizeof(AudioStreamBasicDescription);
			return noErr;
		case kAudioQueueDeviceProperty_SampleRate:
			*outDataSize = sizeof(Float64);
			return noErr;
		case kAudioQueueProperty_CurrentDevice:
			*outDataSize = sizeof(CFStringRef);
			return noErr;
		case kAudioQueueDeviceProperty_NumberChannels:
		case kAudioQueueProperty_EnableLevelMetering:
		case kAudioQueueProperty_ConverterError:
		case kAudioQueueProperty_DecodeBufferSizeFrames:
		case kAudioQueueProperty_EnableTimePitch:
		case kAudioQueueProperty_TimePitchAlgorithm:
		case kAudioQueueProperty_TimePitchBypass:
			*outDataSize = sizeof(UInt32);
			return noErr;
		case kAudioQueueProperty_CurrentLevelMeter:
		case kAudioQueueProperty_CurrentLevelMeterDB:
			*outDataSize = m_format.mChannelsPerFrame * sizeof(AudioQueueLevelMeterState);
			return noErr;
		case kAudioQueueProperty_MagicCookie:
		{
			std::lock_guard<std::mutex> lock(m_queueMutex);
			*outDataSize = UInt32(m_magicCookie.size());
			return noErr;
		}
		case kAudioQueueProperty_ChannelLayout:
		{
			std::lock_guard<std::mutex> lock(m_queueMutex);
			auto it = m_storedProperties.find(inID);
			*outDataSize = (it != m_storedProperties.end()) ? UInt32(it->second.size()) : UInt32(sizeof(AudioChannelLayout));
			return noErr;
		}
	}
	return AudioQueue::getPropertySize(inID, outDataSize);
}

OSStatus AudioQueueOutput::getProperty(AudioQueuePropertyID inID, void *outData, UInt32 *ioDataSize)
{
	if (outData == nullptr || ioDataSize == nullptr)
		return kAudio_ParamError;

	switch (inID)
	{
		case kAudioQueueProperty_StreamDescription:
			return getValue(m_format, outData, ioDataSize);
		case kAudioQueueDeviceProperty_SampleRate:
			return getValue(Float64(m_format.mSampleRate), outData, ioDataSize);
		case kAudioQueueDeviceProperty_NumberChannels:
			return getValue(UInt32(m_format.mChannelsPerFrame), outData, ioDataSize);
		case kAudioQueueProperty_CurrentDevice:
		{
			// NULL stands for the default output device
			std::lock_guard<std::mutex> lock(m_queueMutex);
			CFStringRef device = m_currentDevice ? (CFStringRef) CFRetain(m_currentDevice) : nullptr;
			OSStatus status = getValue(device, outData, ioDataSize);
			if (status != noErr && device != nullptr)
				CFRelease(device);
			return status;
		}
		case kAudioQueueProperty_EnableLevelMetering:
			return getValue(UInt32(m_metering.load() ? 1 : 0), outData, ioDataSize);
		case kAudioQueueProperty_ConverterError:
			return getValue(UInt32(0), outData, ioDataSize);
		case kAudioQueueProperty_CurrentLevelMeter:
		case kAudioQueueProperty_CurrentLevelMeterDB:
		{
			const UInt32 channels = std::min<UInt32>(*ioDataSize / sizeof(AudioQueueLevelMeterState), m_format.mChannelsPerFrame);
			AudioQueueLevelMeterState* levels = static_cast<AudioQueueLevelMeterState*>(outData);
			std::lock_guard<std::mutex> lock(m_meterMutex);

			for (UInt32 i = 0; i < channels; i++)
			{
				AudioQueueLevelMeterState level = (i < m_meters.size()) ? m_meters[i] : AudioQueueLevelMeterState{0, 0};
				if (inID == kAudioQueueProperty_CurrentLevelMeterDB)
				{
					level.mAveragePower = level.mAveragePower > 0 ? std::max(-120.0f, 20.0f * std::log10(level.mAveragePower)) : -120.0f;
					level.mPeakPower = level.mPeakPower > 0 ? std::max(-120.0f, 20.0f * std::log10(level.mPeakPower)) : -120.0f;
				}
				levels[i] = level;
			}
			*ioDataSize = channels * sizeof(AudioQueueLevelMeterState);
			return noErr;
		}
		case kAudioQueueProperty_MagicCookie:
		{
			std::lock_guard<std::mutex> lock(m_queueMutex);
			if (*ioDataSize < m_magicCookie.size())
				return kAudioQueueErr_InvalidPropertySize;
			memcpy(outData, m_magicCookie.data(), m_magicCookie.size());
			*ioDataSize = UInt32(m_magicCookie.size());
			return noErr;
		}
		case kAudioQueueProperty_ChannelLayout:
		case kAudioQueueProperty_DecodeBufferSizeFrames:
		case kAudioQueueProperty_EnableTimePitch:
		case kAudioQueueProperty_TimePitchAlgorithm:
		case kAudioQueueProperty_TimePitchBypass:
		{
			std::lock_guard<std::mutex> lock(m_queueMutex);
			auto it = m_storedProperties.find(inID);
			if (it != m_storedProperties.end())
			{
				if (*ioDataSize < it->second.size())
					return kAudioQueueErr_InvalidPropertySize;
				memcpy(outData, it->second.data(), it->second.size());
				*ioDataSize = UInt32(it->second.size());
				return noErr;
			}

			// the defaults
			switch (inID)
			{
				case kAudioQueueProperty_ChannelLayout:
				{
					AudioChannelLayout layout;
					memset(&layout, 0, sizeof(layout));
					if (m_format.mChannelsPerFrame == 1)
						layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
					else if (m_format.mChannelsPerFrame == 2)
						layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
					else
						layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | m_format.mChannelsPerFrame;
					return getValue(layout, outData, ioDataSize);
				}
				case kAudioQueueProperty_DecodeBufferSizeFrames:
					return getValue(UInt32(2048), outData, ioDataSize);
				case kAudioQueueProperty_TimePitchAlgorithm:
					return getValue(UInt32(kAudioQueueTimePitchAlgorithm_Spectral), outData, ioDataSize);
				default:
					return getValue(UInt32(0), outData, ioDataSize);
			}
		}
	}
	return AudioQueue::getProperty(inID, outData, ioDataSize);
}

OSStatus AudioQueueOutput::setProperty(AudioQueuePropertyID inID, const void *inData, UInt32 inDataSize)
{
	if (inData == nullptr && inDataSize > 0)
		return kAudio_ParamError;

	switch (inID)
	{
		case kAudioQueueProperty_MagicCookie:
		{
			std::lock_guard<std::mutex> renderLock(m_renderMutex);
			std::lock_guard<std::mutex> lock(m_queueMutex);
			const uint8_t* bytes = static_cast<const uint8_t*>(inData);
			m_magicCookie.assign(bytes, bytes + inDataSize);

			if (m_converter != nullptr)
				AudioConverterSetProperty(m_converter, kAudioConverterDecompressionMagicCookie, inDataSize, inData);
			return noErr;
		}
		case kAudioQueueProperty_EnableLevelMetering:
			if (inDataSize < sizeof(UInt32))
				return kAudioQueueErr_InvalidPropertySize;
			m_metering = *static_cast<const UInt32*>(inData) != 0;
			return noErr;
		case kAudioQueueProperty_CurrentDevice:
		{
			// there's only the one output device
			if (inDataSize < sizeof(CFStringRef))
				return kAudioQueueErr_InvalidPropertySize;
			CFStringRef device = *static_cast<const CFStringRef*>(inData);
			std::lock_guard<std::mutex> lock(m_queueMutex);
			if (m_currentDevice != nullptr)
				CFRelease(m_currentDevice);
			m_currentDevice = device ? (CFStringRef) CFRetain(device) : nullptr;
			return noErr;
		}
		case kAudioQueueProperty_ChannelLayout:
		case kAudioQueueProperty_DecodeBufferSizeFrames:
		case kAudioQueueProperty_EnableTimePitch:
		case kAudioQueueProperty_TimePitchAlgorithm:
		case kAudioQueueProperty_TimePitchBypass:
		{
			if (inID != kAudioQueueProperty_ChannelLayout && inDataSize < sizeof(UInt32))
				return kAudioQueueErr_InvalidPropertySize;
			std::lock_guard<std::mutex> lock(m_queueMutex);
			const uint8_t* bytes = static_cast<const uint8_t*>(inData);
			m_storedProperties[inID].assign(bytes, bytes + inDataSize);
			return noErr;
		}
		case kAudioQueueProperty_StreamDescription:
		case kAudioQueueProperty_IsRunning:
		case kAudioQueueDeviceProperty_SampleRate:
		case kAudioQueueDeviceProperty_NumberChannels:
		case kAudioQueueProperty_CurrentLevelMeter:
		case kAudioQueueProperty_CurrentLevelMeterDB:
		case kAudioQueueProperty_ConverterError:
			return kAudioQueueErr_InvalidProperty;
	}
	return AudioQueue::setProperty(inID, inData, inDataSize);
}

OSStatus AudioQueueOutput::enqueueBuffer(AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription *inPacketDescs)
{
	if (inBuffer == nullptr)
		return kAudioQueueErr_InvalidBuffer;
	if (inBuffer->mAudioDataByteSize == 0)
		return kAudioQueueErr_BufferEmpty;

	if (inNumPacketDescs > 0)
	{
		if (inPacketDescs == nullptr)
			return kAudio_ParamError;
		// the descriptions may be the buffer's own
		if (inPacketDescs != inBuffer->mPacketDescriptions)
		{
			if (inBuffer->mPacketDescriptions == nullptr || inNumPacketDescs > inBuffer->mPacketDescriptionCapacity)
			{
				// the client didn't allocate room for them: keep a copy of our own
				AudioStreamPacketDescription* copy = static_cast<AudioStreamPacketDescription*>(
						realloc(inBuffer->mPacketDescriptions, inNumPacketDescs * sizeof(AudioStreamPacketDescription)));
				if (copy == nullptr)
					return kAudio_MemFullError;
				inBuffer->mPacketDescriptions = copy;
				inBuffer->mPacketDescriptionCapacity = inNumPacketDescs;
			}
			memcpy(inBuffer->mPacketDescriptions, inPacketDescs, inNumPacketDescs * sizeof(AudioStreamPacketDescription));
		}
		inBuffer->mPacketDescriptionCount = inNumPacketDescs;
	}
	else if (isVBR())
	{
		// variable bitrate data can't be played without them
		return kAudioQueueErr_BufferEmpty;
	}
	else
		inBuffer->mPacketDescriptionCount = 0;

	{
		std::lock_guard<std::mutex> lock(m_queueMutex);
		m_pendingBuffers.push_back(inBuffer);
	}
	return noErr;
}

OSStatus AudioQueueOutput::getCurrentTime(AudioQueueTimelineRef inTimeline, AudioTimeStamp *outTimeStamp, Boolean *outTimelineDiscontinuity)
{
	(void) inTimeline;
	if (outTimelineDiscontinuity != nullptr)
		*outTimelineDiscontinuity = false;
	if (outTimeStamp == nullptr)
		return kAudio_ParamError;
	memset(outTimeStamp, 0, sizeof(*outTimeStamp));
	outTimeStamp->mSampleTime = (Float64) m_framesRendered.load();
	outTimeStamp->mFlags = kAudioTimeStampSampleTimeValid;
	return noErr;
}

OSStatus AudioQueueOutput::setOfflineRenderFormat(const AudioStreamBasicDescription *inFormat, const AudioChannelLayout *inLayout)
{
	(void) inFormat;
	(void) inLayout;
	STUB();
	return unimpErr;
}

OSStatus AudioQueueOutput::offlineRender(const AudioTimeStamp *inTimestamp, AudioQueueBufferRef ioBuffer, UInt32 inNumberFrames)
{
	(void) inTimestamp;
	(void) ioBuffer;
	(void) inNumberFrames;
	STUB();
	return unimpErr;
}

OSStatus AudioQueueOutput::renderStatic(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
		const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
		AudioBufferList *ioData)
{
	return ((AudioQueueOutput*) inRefCon)->renderCallback(ioActionFlags, inTimeStamp,
			inBusNumber, inNumberFrames, ioData);
}

OSStatus AudioQueueOutput::renderCallback(AudioUnitRenderActionFlags *ioActionFlags,
		const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
		AudioBufferList *ioData)
{
	(void) inTimeStamp;
	(void) inBusNumber;

	std::deque<AudioQueueBufferRef> completed;
	bool anyData = false;
	{
		std::lock_guard<std::mutex> renderLock(m_renderMutex);
		if (m_converter != nullptr)
			anyData = renderWithConverter(ioData, inNumberFrames, completed);
		else
			anyData = renderDirect(ioData, completed);
		m_framesRendered += inNumberFrames;
		checkForStop();
	}
	applyVolume(ioData);
	if (m_metering)
		updateMeters(ioData, !anyData);
	if (!anyData && ioActionFlags != nullptr)
		*ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
	returnBuffers(completed);
	return noErr;
}

bool AudioQueueOutput::renderDirect(AudioBufferList *ioData, std::deque<AudioQueueBufferRef>& completed)
{
	bool anyData = false;

	std::lock_guard<std::mutex> lock(m_queueMutex);
	for (UInt32 i = 0; i < ioData->mNumberBuffers; i++)
	{
		AudioBuffer& buffer = ioData->mBuffers[i];
		char* dst = (char*) buffer.mData;
		UInt32 remaining = buffer.mDataByteSize;

		while (remaining > 0)
		{
			if (m_pendingBuffers.empty())
				break;

			AudioQueueBufferRef src = m_pendingBuffers.front();
			if (m_bufferOffset >= src->mAudioDataByteSize)
			{
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				completed.push_back(src);
				continue;
			}

			UInt32 chunk = src->mAudioDataByteSize - m_bufferOffset;
			if (chunk > remaining)
				chunk = remaining;
			memcpy(dst, (const char*) src->mAudioData + m_bufferOffset, chunk);
			m_bufferOffset += chunk;
			dst += chunk;
			remaining -= chunk;
			anyData = true;
		}

		// hand a played buffer back right away rather than on the next round
		if (!m_pendingBuffers.empty() && m_bufferOffset >= m_pendingBuffers.front()->mAudioDataByteSize)
		{
			completed.push_back(m_pendingBuffers.front());
			m_pendingBuffers.pop_front();
			m_bufferOffset = 0;
		}

		if (remaining > 0)
			memset(dst, 0, remaining);
	}
	return anyData;
}

OSStatus AudioQueueOutput::converterInputStatic(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets,
		AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription,
		void *inUserData)
{
	(void) inConverter;
	ConverterContext* context = (ConverterContext*) inUserData;
	return context->queue->converterInput(ioNumberDataPackets, ioData,
			outDataPacketDescription, *context->completed);
}

OSStatus AudioQueueOutput::converterInput(UInt32 *ioNumberDataPackets, AudioBufferList *ioData,
		AudioStreamPacketDescription **outDataPacketDescription, std::deque<AudioQueueBufferRef>& completed)
{
	if (outDataPacketDescription != nullptr)
		*outDataPacketDescription = nullptr;

	std::lock_guard<std::mutex> lock(m_queueMutex);

	// asking for more means the converter is done with what it got last time
	if (m_handedOut != nullptr)
	{
		completed.push_back(m_handedOut);
		m_handedOut = nullptr;
	}

	ioData->mBuffers[0].mNumberChannels = m_format.mChannelsPerFrame;

	while (!m_pendingBuffers.empty() && *ioNumberDataPackets > 0)
	{
		AudioQueueBufferRef src = m_pendingBuffers.front();
		UInt32 packets;

		if (isVBR())
		{
			// hand over packets as the client described them, with offsets relative to the data we pass
			const UInt32 count = src->mPacketDescriptionCount;
			if (m_bufferOffset >= count)
			{
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				completed.push_back(src);
				continue;
			}

			packets = std::min(count - m_bufferOffset, *ioNumberDataPackets);
			const AudioStreamPacketDescription* descs = src->mPacketDescriptions + m_bufferOffset;
			const SInt64 base = descs[0].mStartOffset;
			SInt64 end = base;

			m_converterPackets.assign(descs, descs + packets);
			for (AudioStreamPacketDescription& desc : m_converterPackets)
			{
				end = std::max(end, desc.mStartOffset + SInt64(desc.mDataByteSize));
				desc.mStartOffset -= base;
			}
			if (base < 0 || end > SInt64(src->mAudioDataByteSize))
			{
				// bogus descriptions: skip the buffer
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				completed.push_back(src);
				continue;
			}

			ioData->mBuffers[0].mData = (char*) src->mAudioData + base;
			ioData->mBuffers[0].mDataByteSize = UInt32(end - base);
			if (outDataPacketDescription != nullptr)
				*outDataPacketDescription = m_converterPackets.data();
			m_bufferOffset += packets;

			if (m_bufferOffset >= count)
			{
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				m_handedOut = src;
			}
		}
		else
		{
			const UInt32 bytesPerPacket = m_format.mBytesPerPacket;
			if (m_bufferOffset + bytesPerPacket > src->mAudioDataByteSize)
			{
				// done with it (or what's left isn't a whole packet)
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				completed.push_back(src);
				continue;
			}

			packets = std::min((src->mAudioDataByteSize - m_bufferOffset) / bytesPerPacket, *ioNumberDataPackets);
			ioData->mBuffers[0].mData = (char*) src->mAudioData + m_bufferOffset;
			ioData->mBuffers[0].mDataByteSize = packets * bytesPerPacket;
			m_bufferOffset += packets * bytesPerPacket;

			if (m_bufferOffset + bytesPerPacket > src->mAudioDataByteSize)
			{
				m_pendingBuffers.pop_front();
				m_bufferOffset = 0;
				m_handedOut = src;
			}
		}

		*ioNumberDataPackets = packets;
		return noErr;
	}

	// nothing queued right now
	*ioNumberDataPackets = 0;
	ioData->mBuffers[0].mData = nullptr;
	ioData->mBuffers[0].mDataByteSize = 0;
	return noErr;
}

bool AudioQueueOutput::renderWithConverter(AudioBufferList *ioData, UInt32 inNumberFrames, std::deque<AudioQueueBufferRef>& completed)
{
	UInt32 sizes[kMaxMeteredChannels];
	const UInt32 numBuffers = std::min(ioData->mNumberBuffers, kMaxMeteredChannels);

	for (UInt32 i = 0; i < numBuffers; i++)
		sizes[i] = ioData->mBuffers[i].mDataByteSize;

	ConverterContext context;
	context.queue = this;
	context.completed = &completed;

	UInt32 packets = inNumberFrames;
	OSStatus status = AudioConverterFillComplexBuffer(m_converter, converterInputStatic, &context,
			&packets, ioData, nullptr);

	bool anyData = false;
	for (UInt32 i = 0; i < numBuffers; i++)
	{
		AudioBuffer& buffer = ioData->mBuffers[i];
		UInt32 produced = (status == noErr) ? std::min(buffer.mDataByteSize, sizes[i]) : 0;

		if (produced > 0)
			anyData = true;
		if (buffer.mData != nullptr && produced < sizes[i])
			memset((char*) buffer.mData + produced, 0, sizes[i] - produced);
		buffer.mDataByteSize = sizes[i];
	}
	return anyData;
}

// Whether the samples are plain native-endian floats or 16-bit integers, which is what volume and metering handle
static bool isSimpleFormat(const AudioStreamBasicDescription& format, bool* isFloat)
{
	if (format.mFormatID != kAudioFormatLinearPCM || (format.mFormatFlags & kAudioFormatFlagIsBigEndian))
		return false;

	*isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
	if (*isFloat)
		return format.mBitsPerChannel == 32;
	return (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) && format.mBitsPerChannel == 16;
}

void AudioQueueOutput::applyVolume(AudioBufferList *ioData)
{
	AudioQueueParameterValue volume = m_volume.load();
	bool isFloat;

	if (volume == 1.0f || !isSimpleFormat(m_unitFormat, &isFloat))
		return;

	for (UInt32 i = 0; i < ioData->mNumberBuffers; i++)
	{
		AudioBuffer& buffer = ioData->mBuffers[i];
		if (buffer.mData == nullptr)
			continue;
		if (isFloat)
		{
			Float32* samples = (Float32*) buffer.mData;
			size_t count = buffer.mDataByteSize / sizeof(Float32);
			for (size_t j = 0; j < count; j++)
				samples[j] *= volume;
		}
		else
		{
			SInt16* samples = (SInt16*) buffer.mData;
			size_t count = buffer.mDataByteSize / sizeof(SInt16);
			for (size_t j = 0; j < count; j++)
				samples[j] = (SInt16) (samples[j] * volume);
		}
	}
}

void AudioQueueOutput::updateMeters(const AudioBufferList *ioData, bool silent)
{
	const UInt32 channels = std::min(m_unitFormat.mChannelsPerFrame, kMaxMeteredChannels);
	double sums[kMaxMeteredChannels] = {0};
	float peaks[kMaxMeteredChannels] = {0};
	size_t frames = 0;
	bool isFloat;

	if (!silent && channels > 0 && isSimpleFormat(m_unitFormat, &isFloat))
	{
		const bool interleaved = !(m_unitFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved);
		const size_t sampleSize = isFloat ? sizeof(Float32) : sizeof(SInt16);

		for (UInt32 b = 0; b < ioData->mNumberBuffers; b++)
		{
			const AudioBuffer& buffer = ioData->mBuffers[b];
			const size_t count = buffer.mDataByteSize / sampleSize;
			const UInt32 stride = interleaved ? channels : 1;

			if (buffer.mData == nullptr)
				continue;
			for (size_t j = 0; j < count; j++)
			{
				const UInt32 c = interleaved ? UInt32(j % stride) : b;
				if (c >= channels)
					continue;
				float v = isFloat ? ((const Float32*) buffer.mData)[j] : ((const SInt16*) buffer.mData)[j] / 32768.0f;
				v = std::fabs(v);
				sums[c] += double(v) * v;
				peaks[c] = std::max(peaks[c], v);
			}
			frames = std::max(frames, count / stride);
		}
	}

	std::lock_guard<std::mutex> lock(m_meterMutex);
	m_meters.resize(channels);
	for (UInt32 c = 0; c < channels; c++)
	{
		m_meters[c].mAveragePower = frames ? float(std::sqrt(sums[c] / frames)) : 0.0f;
		m_meters[c].mPeakPower = peaks[c];
	}
}

void AudioQueueOutput::checkForStop()
{
	bool stopNow = false;
	{
		std::lock_guard<std::mutex> lock(m_queueMutex);
		if (m_stopping && m_pendingBuffers.empty())
		{
			m_stopping = false;
			stopNow = true;
		}
	}
	if (!stopNow)
		return;

	// everything has been played; stopping waits for this render callback, so it can't happen here
	std::shared_ptr<CallbackState> state = m_callbackState;
	postCallbackBlock(^{
		std::lock_guard<std::recursive_mutex> lock(state->mutex);
		if (!state->alive)
			return;
		stopUnit();
		// hands back what the converter held on to
		reset();
	});
}

void AudioQueueOutput::postCallbackBlock(void (^block)(void))
{
	if (m_runloop != nullptr)
	{
		CFStringRef mode = (m_runloopMode != nullptr) ? m_runloopMode : kCFRunLoopCommonModes;
		CFRunLoopPerformBlock(m_runloop, mode, block);
		CFRunLoopWakeUp(m_runloop);
	}
	else
		dispatch_async(m_callbackQueue, block);
}

void AudioQueueOutput::returnBuffers(const std::deque<AudioQueueBufferRef>& buffers)
{
	if (buffers.empty())
		return;

	std::shared_ptr<CallbackState> state = m_callbackState;
	for (AudioQueueBufferRef buffer : buffers)
	{
		postCallbackBlock(^{
			std::lock_guard<std::recursive_mutex> lock(state->mutex);
			// the queue may have been disposed of since
			if (!state->alive)
				return;
			if (m_callbackBlock != nullptr)
				m_callbackBlock(this, buffer);
			else
				m_callback(m_userData, this, buffer);
		});
	}
}

OSStatus AudioQueueOutput::create(const AudioStreamBasicDescription *inFormat,
		AudioQueueOutputCallback inCallbackProc,
	void *inUserData, CFRunLoopRef inCallbackRunLoop,
	CFStringRef inCallbackRunLoopMode, UInt32 inFlags,
		AudioQueueOutput** newQueue)
{
	if (inFormat == nullptr || inCallbackProc == nullptr || newQueue == nullptr)
		return kAudio_ParamError;

	AudioQueueOutput* queue = new AudioQueueOutput(inFormat, inCallbackProc, inUserData,
			inCallbackRunLoop, inCallbackRunLoopMode, inFlags);
	OSStatus status = queue->checkFormat();
	if (status != noErr)
	{
		delete queue;
		*newQueue = nullptr;
		return status;
	}
	*newQueue = queue;
	return noErr;
}

OSStatus AudioQueueOutput::create(const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
		dispatch_queue_t inCallbackQueue, AudioQueueOutputCallbackBlock inCallbackBlock,
		AudioQueueOutput** newQueue)
{
	if (inFormat == nullptr || inCallbackQueue == nullptr || inCallbackBlock == nullptr || newQueue == nullptr)
		return kAudio_ParamError;

	AudioQueueOutput* queue = new AudioQueueOutput(inFormat, inFlags, inCallbackQueue, inCallbackBlock);
	OSStatus status = queue->checkFormat();
	if (status != noErr)
	{
		delete queue;
		*newQueue = nullptr;
		return status;
	}
	*newQueue = queue;
	return noErr;
}
