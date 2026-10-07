/*
This file is part of Darling.

Copyright (C) 2020 Lubos Dolezel

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "AUHAL.h"
#include <cstddef>
#include <iostream>

#pragma GCC visibility push(default)
AUDIOCOMPONENT_ENTRY(AUOutputBaseFactory, AUHAL);
#pragma GCC visibility pop

enum {
	kOutputBus = 0,
	kInputBus
};

AUHAL::AUHAL(AudioComponentInstance inInstance, bool supportRecording)
: AUBase(inInstance, 1, supportRecording ? 1 : 0)
{
	UInt32 propSize = sizeof(AudioDeviceID);
	AudioHardwareGetProperty(kAudioHardwarePropertyDefaultOutputDevice, &propSize, &m_outputDevice);
	AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &propSize, &m_inputDevice);
}

AUHAL::~AUHAL()
{
	Stop();
}

bool AUHAL::CanScheduleParameters() const
{
	return true;
}

bool AUHAL::StreamFormatWritable(AudioUnitScope scope, AudioUnitElement element)
{
	// apps set the format before initializing the unit (and may change it after)
	return !m_running;
}

// Any linear PCM the sound server plays: interleaved integers or floats, or non-interleaved
// 32-bit floats (Core Audio's canonical format), which playback interleaves.
bool AUHAL::ValidFormat(AudioUnitScope scope, AudioUnitElement element, const CAStreamBasicDescription& format)
{
	if (format.mFormatID != kAudioFormatLinearPCM || format.mChannelsPerFrame == 0 ||
		format.mChannelsPerFrame > 16 || format.mSampleRate <= 0)
		return false;

	if (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
		return (format.mFormatFlags & kAudioFormatFlagIsFloat) && format.mBitsPerChannel == 32;

	if (format.mFormatFlags & kAudioFormatFlagIsFloat)
		return format.mBitsPerChannel == 32;
	return format.mBitsPerChannel == 8 || format.mBitsPerChannel == 16 ||
		format.mBitsPerChannel == 24 || format.mBitsPerChannel == 32;
}

OSStatus AUHAL::Version()
{
	return 1;
}

// Provide data from the microphone
OSStatus AUHAL::Render(AudioUnitRenderActionFlags& ioActionFlags, const AudioTimeStamp& inTimeStamp, UInt32 inNumberFrames)
{
	std::unique_lock<std::mutex> lk(m_dataAvailableMutex);

	m_dataAvailableCV.wait(lk, [=]{ return m_dataAvailable; });

	AudioBufferList& abl = GetOutput(kInputBus)->GetBufferList();

	// TODO: Prepare for non-interleaved audio
	UInt32 howMuch = std::min<UInt32>(abl.mBuffers[0].mDataByteSize, m_bufferUsed);
	memcpy(abl.mBuffers[0].mData, m_buffer.get(), howMuch);
	abl.mBuffers[0].mDataByteSize = howMuch;

	return noErr;
}

OSStatus AUHAL::Start()
{
	if (m_running)
		return noErr;

	if (m_enableOutput)
	{
		// std::cout << "Output is enabled, starting playback\n";
		AudioDeviceCreateIOProcID(m_outputDevice, playbackCallback, this, &m_outputProcID);

		// m_auhalData.open("/tmp/auhal.raw", std::ios_base::binary | std::ios_base::out);

		CAStreamBasicDescription desc = GetStreamFormat(kAudioUnitScope_Input, kOutputBus);

		// the device plays interleaved samples
		if (desc.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
		{
			desc.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
			desc.mBytesPerFrame = desc.mBytesPerPacket = desc.mChannelsPerFrame * (desc.mBitsPerChannel / 8);
		}
		AudioDeviceSetProperty(m_outputDevice, nullptr, 0, false, kAudioDevicePropertyStreamFormat, sizeof(AudioStreamBasicDescription), &desc);
		AudioDeviceStart(m_outputDevice, m_outputProcID);
	}
	if (m_enableInput)
	{
		AudioDeviceCreateIOProcID(m_inputDevice, recordCallback, this, &m_inputProcID);
		const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Output, kInputBus);
		AudioDeviceSetProperty(m_inputDevice, nullptr, 0, true, kAudioDevicePropertyStreamFormat, sizeof(AudioStreamBasicDescription), &desc);
		AudioDeviceStart(m_inputDevice, m_inputProcID);
	}

	m_running = m_enableOutput || m_enableInput;
	return noErr;
}

OSStatus AUHAL::Stop()
{
	if (!m_running)
		return noErr;

	if (m_outputProcID)
	{
		AudioDeviceStop(m_outputDevice, m_outputProcID);
		AudioDeviceDestroyIOProcID(m_outputDevice, m_outputProcID);
		m_outputProcID = 0;
	}
	if (m_inputProcID)
	{
		AudioDeviceStop(m_inputDevice, m_inputProcID);
		AudioDeviceDestroyIOProcID(m_inputDevice, m_inputProcID);
		m_inputProcID = 0;
	}

	m_running = false;
	return noErr;
}

OSStatus AUHAL::SetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, const void* inData, UInt32 inDataSize)
{
	switch (inID)
	{
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			ca_require(inDataSize == sizeof(AURenderCallbackStruct), InvalidPropertyValue);
			const AURenderCallbackStruct* cb = static_cast<const AURenderCallbackStruct*>(inData);
			
			m_outputAvailableCb = *cb;

			PropertyChanged(inID, inScope, inElement);
			return noErr;
		}
		case kAudioOutputUnitProperty_EnableIO:
		{
			ca_require(inDataSize == sizeof(UInt32), InvalidPropertyValue);

			const bool enable = *((const UInt32*) inData);

			if (inElement == kOutputBus)
			{
				m_enableOutput = enable;
				PropertyChanged(inID, inScope, inElement);
			}
			else if (inElement == kInputBus)
			{
				m_enableInput = enable;
				PropertyChanged(inID, inScope, inElement);
			}
			else
				return kAudioUnitErr_InvalidElement;

			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			ca_require(inDataSize == sizeof(AudioDeviceID), InvalidPropertyValue);
			const AudioDeviceID* dev = static_cast<const AudioDeviceID*>(inData);

			if (inElement == kOutputBus)
			{
				m_outputDevice = *dev;
				PropertyChanged(inID, inScope, inElement);
			}
			else if (inElement == kInputBus)
			{
				m_inputDevice = *dev;
				PropertyChanged(inID, inScope, inElement);
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
	}
	return AUBase::SetProperty(inID, inScope, inElement, inData, inDataSize);
InvalidPropertyValue:
	return kAudioUnitErr_InvalidPropertyValue;
}

OSStatus AUHAL::GetPropertyInfo(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, UInt32& outDataSize, Boolean& outWritable)
{
	switch (inID)
	{
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			outDataSize = sizeof(AURenderCallbackStruct);
			outWritable = true;
			break;
		}
		case kAudioOutputUnitProperty_EnableIO:
		{
			outDataSize = sizeof(UInt32);
			outWritable = true;
			return noErr;
		}
		case kAudioOutputUnitProperty_HasIO:
		{
			outDataSize = sizeof(UInt32);
			outWritable = false;
			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			outDataSize = sizeof(AudioDeviceID);
			outWritable = true;
			return noErr;
		}
	}
	return AUBase::GetPropertyInfo(inID, inScope, inElement, outDataSize, outWritable);
}

OSStatus AUHAL::GetProperty(AudioUnitPropertyID inID, AudioUnitScope inScope, AudioUnitElement inElement, void* outData)
{
	switch (inID)
	{
		case kAudioOutputUnitProperty_SetInputCallback:
		{
			memcpy(outData, &m_outputAvailableCb, sizeof(m_outputAvailableCb));
			return noErr;
		}
		case kAudioOutputUnitProperty_EnableIO:
		case kAudioOutputUnitProperty_HasIO:
		{
			if (inElement == kOutputBus)
			{
				UInt32 value = m_enableOutput;
				memcpy(&outData, &value, sizeof(value));
			}
			else if (inElement == kInputBus)
			{
				UInt32 value = m_enableInput;
				memcpy(&outData, &value, sizeof(value));
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
		case kAudioOutputUnitProperty_CurrentDevice:
		{
			if (inElement == kOutputBus)
			{
				memcpy(outData, &m_outputDevice, sizeof(m_outputDevice));
			}
			else if (inElement == kInputBus)
			{
				memcpy(outData, &m_inputDevice, sizeof(m_inputDevice));
			}
			else
				return kAudioUnitErr_InvalidElement;
			return noErr;
		}
	}
	return AUBase::GetProperty(inID, inScope, inElement, outData);
}

OSStatus AUHAL::playbackCallback(AudioObjectID inObjectID,
	const AudioTimeStamp* inNow, const AudioBufferList* inInputData,
	const AudioTimeStamp* inInputTime,
	AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime,
	void* inClientData)
{
	AUHAL* This = static_cast<AUHAL*>(inClientData);
	return This->doPlayback(inNow, outOutputData, inOutputTime);
}

OSStatus AUHAL::recordCallback(AudioObjectID inObjectID,
	const AudioTimeStamp* inNow, const AudioBufferList* inInputData,
	const AudioTimeStamp* inInputTime,
	AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime,
	void* inClientData)
{
	AUHAL* This = static_cast<AUHAL*>(inClientData);
	return This->doRecord(inNow, inInputData, inInputTime);
}

OSStatus AUHAL::doPlayback(const AudioTimeStamp* inNow, AudioBufferList* outOutputData, const AudioTimeStamp* inOutputTime)
{
	// std::cout << "AUHAL::DoPlayback()\n";
	if (!HasInput(0))
	{
		// std::cerr << "No connection\n";
		return kAudioUnitErr_NoConnection;
	}

	OSStatus result = noErr;
	AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
	const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Input, kOutputBus);
	const UInt32 channels = desc.mChannelsPerFrame;

	if (desc.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
	{
		// pull one buffer per channel, then interleave them into the device's buffer
		const UInt32 nFrames = outOutputData->mBuffers[0].mDataByteSize / (channels * sizeof(float));
		const size_t listSize = offsetof(AudioBufferList, mBuffers) + channels * sizeof(AudioBuffer);

		if (m_planar.size() < size_t(nFrames) * channels)
			m_planar.resize(size_t(nFrames) * channels);
		if (m_planarList.size() < listSize)
			m_planarList.resize(listSize);

		AudioBufferList* planar = reinterpret_cast<AudioBufferList*>(m_planarList.data());
		planar->mNumberBuffers = channels;
		for (UInt32 c = 0; c < channels; c++)
		{
			planar->mBuffers[c].mNumberChannels = 1;
			planar->mBuffers[c].mDataByteSize = nFrames * sizeof(float);
			planar->mBuffers[c].mData = m_planar.data() + size_t(c) * nFrames;
		}

		result = GetInput(kOutputBus)->PullInputWithBufferList(flags, *inNow, kOutputBus, nFrames, planar);

		float* out = static_cast<float*>(outOutputData->mBuffers[0].mData);
		for (UInt32 c = 0; c < channels; c++)
		{
			// the source may have handed back buffers of its own
			const float* in = static_cast<const float*>(planar->mBuffers[c].mData);
			for (UInt32 f = 0; f < nFrames; f++)
				out[size_t(f) * channels + c] = (result == noErr && in != nullptr) ? in[f] : 0.0f;
		}
		outOutputData->mBuffers[0].mDataByteSize = nFrames * channels * sizeof(float);
		return result;
	}

	const UInt32 nFrames = outOutputData->mBuffers[0].mDataByteSize / desc.mBytesPerFrame;
	result = GetInput(kOutputBus)->PullInputWithBufferList(flags, *inNow, kOutputBus, nFrames, outOutputData);

	// std::cout << "Pull result: " << result << std::endl;
	// std::cout << "Bytes: " << outOutputData->mBuffers[0].mDataByteSize << std::endl;
	// m_auhalData.write((char*) outOutputData->mBuffers[0].mData, outOutputData->mBuffers[0].mDataByteSize);
	// m_auhalData.flush();

	return result;
}

OSStatus AUHAL::doRecord(const AudioTimeStamp* inNow, const AudioBufferList* inInputData, const AudioTimeStamp* inInputTime)
{
	// TODO: Prepare for non-interleaved audio
	std::unique_lock<std::mutex> lk(m_dataAvailableMutex);

	if (m_bufferSize < inInputData->mBuffers[0].mDataByteSize)
	{
		m_buffer.reset(new uint8_t[inInputData->mBuffers[0].mDataByteSize]);
		m_bufferSize = inInputData->mBuffers[0].mDataByteSize;
	}

	m_bufferUsed = inInputData->mBuffers[0].mDataByteSize;
	memcpy(m_buffer.get(), inInputData->mBuffers[0].mData, m_bufferUsed);

	m_dataAvailable = true;

	lk.unlock();
	m_dataAvailableCV.notify_one();

	if (m_outputAvailableCb.inputProc)
	{
		AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PostRender;
		const CAStreamBasicDescription& desc = GetStreamFormat(kAudioUnitScope_Output, kInputBus);
		UInt32 numFrames = m_bufferUsed / desc.mBytesPerFrame;

		m_outputAvailableCb.inputProc(m_outputAvailableCb.inputProcRefCon, &flags, inInputTime, kInputBus, numFrames, nullptr);
	}

	return noErr;
}

// AUDispatch.cpp doesn't implement dispatch code for AudioOutputUnits
OSStatus AUHAL::ComponentEntryDispatch(ComponentParameters *params, AUHAL *This)
{
	if (This == NULL) return kAudio_ParamError;

	OSStatus result = noErr;

	switch (params->what)
	{
		case kComponentCanDoSelect:
			switch (GetSelectorForCanDo(params))
			{
				case kAudioOutputUnitStartSelect:
				case kAudioOutputUnitStopSelect:
					return 1;
			}
			break;
		case kAudioOutputUnitStartSelect:
		{
			CAMutex::Locker lock(This->GetMutex());
			return This->Start();
		}
		case kAudioOutputUnitStopSelect:
		{
			CAMutex::Locker lock(This->GetMutex());
			return This->Stop();
		}
	}

	return AUBase::ComponentEntryDispatch(params, This);
}
