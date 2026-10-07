#ifndef AUDIOQUEUEOUTPUT_H
#define	AUDIOQUEUEOUTPUT_H
#include "AudioQueueBase.h"
#include <AudioToolbox/AUComponent.h>
#include <AudioToolbox/AudioConverter.h>
#include <dispatch/dispatch.h>
#include <atomic>
#include <deque>
#include <map>
#include <memory>

// Plays the buffers the client enqueues through the default output unit, converting them
// (and decoding compressed formats) when the unit can't take the queue's format as is.
class AudioQueueOutput : public AudioQueue
{
public:
	AudioQueueOutput(const AudioStreamBasicDescription *inFormat,
			AudioQueueOutputCallback inCallbackProc,
		void *inUserData, CFRunLoopRef inCallbackRunLoop,
		CFStringRef inCallbackRunLoopMode, UInt32 inFlags);
	AudioQueueOutput(const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
			dispatch_queue_t inCallbackQueue, AudioQueueOutputCallbackBlock inCallbackBlock);

	virtual ~AudioQueueOutput();

	virtual OSStatus start(const AudioTimeStamp *inStartTime) override;
	virtual OSStatus prime(UInt32 inNumberOfFramesToPrepare, UInt32 *outNumberOfFramesPrepared) override;
	virtual OSStatus flush() override;
	virtual OSStatus stop(Boolean inImmediate) override;
	virtual OSStatus pause() override;
	virtual OSStatus reset() override;

	virtual OSStatus setOfflineRenderFormat(const AudioStreamBasicDescription *inFormat, const AudioChannelLayout *inLayout) override;
	virtual OSStatus offlineRender(const AudioTimeStamp *inTimestamp, AudioQueueBufferRef ioBuffer, UInt32 inNumberFrames) override;

	virtual OSStatus dispose(Boolean inImmediate) override;

	virtual OSStatus getParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue *outValue) override;
	virtual OSStatus setParameter(AudioQueueParameterID inParamID, AudioQueueParameterValue inValue) override;

	virtual OSStatus getProperty(AudioQueuePropertyID inID, void *outData, UInt32 *ioDataSize) override;
	virtual OSStatus setProperty(AudioQueuePropertyID inID, const void *inData, UInt32 inDataSize) override;
	virtual OSStatus getPropertySize(AudioQueuePropertyID inID, UInt32 *outDataSize) override;

	virtual OSStatus enqueueBuffer(AudioQueueBufferRef inBuffer, UInt32 inNumPacketDescs, const AudioStreamPacketDescription *inPacketDescs) override;
	virtual OSStatus getCurrentTime(AudioQueueTimelineRef inTimeline, AudioTimeStamp *outTimeStamp, Boolean *outTimelineDiscontinuity) override;

	static OSStatus create(const AudioStreamBasicDescription *inFormat,
			AudioQueueOutputCallback inCallbackProc,
		void *inUserData, CFRunLoopRef inCallbackRunLoop,
		CFStringRef inCallbackRunLoopMode, UInt32 inFlags,
			AudioQueueOutput** newQueue);
	static OSStatus create(const AudioStreamBasicDescription *inFormat, UInt32 inFlags,
			dispatch_queue_t inCallbackQueue, AudioQueueOutputCallbackBlock inCallbackBlock,
			AudioQueueOutput** newQueue);
private:
	// Shared with the blocks that call the client back, which may run after the queue is gone.
	// The mutex is held while the client's callback runs, so disposing waits for one in progress.
	struct CallbackState
	{
		std::recursive_mutex mutex;
		bool alive = true;
	};

	static OSStatus renderStatic(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
			const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
			AudioBufferList *ioData);
	static OSStatus converterInputStatic(AudioConverterRef inConverter, UInt32 *ioNumberDataPackets,
			AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription,
			void *inUserData);
	struct ConverterContext
	{
		AudioQueueOutput* queue;
		std::deque<AudioQueueBufferRef>* completed;
	};

	OSStatus checkFormat();
	OSStatus createOutputUnit();
	OSStatus createConverter();
	OSStatus renderCallback(AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp,
			UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);
	OSStatus converterInput(UInt32 *ioNumberDataPackets, AudioBufferList *ioData,
			AudioStreamPacketDescription **outDataPacketDescription, std::deque<AudioQueueBufferRef>& completed);
	bool renderDirect(AudioBufferList *ioData, std::deque<AudioQueueBufferRef>& completed);
	bool renderWithConverter(AudioBufferList *ioData, UInt32 inNumberFrames, std::deque<AudioQueueBufferRef>& completed);
	void applyVolume(AudioBufferList *ioData);
	void updateMeters(const AudioBufferList *ioData, bool silent);
	void checkForStop();
	void stopUnit();
	void postCallbackBlock(void (^block)(void));
	void returnBuffers(const std::deque<AudioQueueBufferRef>& buffers);
	bool isVBR() const { return m_format.mBytesPerPacket == 0; }

	AudioQueueOutputCallback m_callback = nullptr;
	AudioQueueOutputCallbackBlock m_callbackBlock = nullptr;
	// where callbacks go when there's no run loop: the client's queue or our own
	dispatch_queue_t m_callbackQueue = nullptr;
	std::shared_ptr<CallbackState> m_callbackState;

	AudioUnit m_outputUnit = nullptr;
	AudioConverterRef m_converter = nullptr;
	// what the output unit is fed with
	AudioStreamBasicDescription m_unitFormat;
	std::atomic<AudioQueueParameterValue> m_volume;
	std::atomic<UInt64> m_framesRendered;
	std::mutex m_stateMutex;
	std::mutex m_renderMutex;
	std::mutex m_queueMutex;
	std::deque<AudioQueueBufferRef> m_pendingBuffers;
	// how far into the front buffer playback is: bytes, or packets for variable bitrate formats
	UInt32 m_bufferOffset = 0;
	// the buffer the converter was handed last; it may hold on to the data until it asks for more
	AudioQueueBufferRef m_handedOut = nullptr;
	std::vector<AudioStreamPacketDescription> m_converterPackets;
	bool m_stopping = false;

	std::vector<uint8_t> m_magicCookie;
	// properties that are kept for the client but have no effect on playback
	std::map<AudioQueuePropertyID, std::vector<uint8_t>> m_storedProperties;
	CFStringRef m_currentDevice = nullptr;

	std::atomic<bool> m_metering;
	std::mutex m_meterMutex;
	std::vector<AudioQueueLevelMeterState> m_meters;
};

#endif	/* AUDIOQUEUEOUTPUT_H */
