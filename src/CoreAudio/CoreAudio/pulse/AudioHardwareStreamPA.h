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

#ifndef AUDIOHARDWARESTREAMPA_H
#define AUDIOHARDWARESTREAMPA_H
#include "../AudioHardwareStream.h"
#include <pulse/pulseaudio.h>
#include <CoreAudio/CoreAudioTypes.h>
#include <CoreAudio/AudioHardware.h>
#include "AudioHardwareImplPA.h"
#include <memory>

class AudioHardwareStreamPA : public AudioHardwareStream
{
public:
	AudioHardwareStreamPA(AudioHardwareImplPA* hw, AudioDeviceIOProc callback, void* clientData);
	~AudioHardwareStreamPA();

	// Creates the PulseAudio stream once the context is ready. Called once the object is fully constructed,
	// because that ends up in the subclass' start().
	void connect();
	void stop(/*void(^cbDone)()*/) override;
protected:
	// Connects the new stream; runs on the PulseAudio loop's queue, like the stream callbacks
	virtual void start();
	void transformSignedUnsigned(AudioBufferList* abl) const;
private:
	void setUp(pa_context* context);
protected:
	AudioDeviceIOProc m_callback;
	void* m_clientData;
	pa_stream* m_stream = nullptr;
	// the device's format when the stream was started (another client may change it later)
	AudioStreamBasicDescription m_asbd;
	bool m_convertSignedUnsigned = false;

	bool m_running = false;
	// Points back at the stream until it's stopped. Blocks waiting for the context and the stream callbacks hold
	// a reference, so they can tell whether the stream is gone - the client may stop it from within its IOProc.
	std::shared_ptr<AudioHardwareStreamPA*> m_self;
};

#endif /* AUDIOHARDWARESTREAMPA_H */

