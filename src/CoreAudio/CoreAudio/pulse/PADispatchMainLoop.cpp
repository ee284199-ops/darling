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
#include "PADispatchMainLoop.h"
#include <iostream>
#include <sys/stat.h>

// marks the loop's queue, so code can tell whether it's already running on it
static char queueKey;

PADispatchMainLoop::PADispatchMainLoop()
{
	// Create GCD queue
	m_queue = dispatch_queue_create("org.darlinghq.coreaudio.pulseaudio", nullptr);
	dispatch_queue_set_specific(m_queue, &queueKey, this, nullptr);

	// PulseAudio expects the event loop to be suspended while we're creating the context.
	// I couldn't find any mention of this in the documentation, but figured it out the hard way.
	dispatch_suspend(m_queue);
}

static void dual_destroy(dual_source* dual);

PADispatchMainLoop::~PADispatchMainLoop()
{
	resume();
	for (auto& [fd, dual] : m_ioSources)
		dual_destroy(dual);
	dispatch_release(m_queue);
}

void PADispatchMainLoop::suspend()
{
	if (!m_suspended)
	{
		dispatch_suspend(m_queue);
		m_suspended = true;
	}
}

void PADispatchMainLoop::resume()
{
	if (m_suspended)
	{
		dispatch_resume(m_queue);
		m_suspended = false;
	}
}

void PADispatchMainLoop::async(void (^block)())
{
	dispatch_async(m_queue, block);
}

void PADispatchMainLoop::sync(void (^block)())
{
	if (onQueue())
		block();
	else
		dispatch_sync(m_queue, block);
}

bool PADispatchMainLoop::onQueue() const
{
	return dispatch_get_specific(&queueKey) == this;
}

pa_mainloop_api* PADispatchMainLoop::getAPI()
{
	if (!m_api.userdata)
	{
		m_api.io_new = io_new;
		m_api.io_enable = io_enable;
		m_api.io_free = io_free;
		m_api.io_set_destroy = io_set_destroy;

		m_api.time_new = time_new;
		m_api.time_restart = time_restart;
		m_api.time_set_destroy = time_set_destroy;
		m_api.time_free = time_free;

		m_api.defer_new = defer_new;
		m_api.defer_set_destroy = defer_set_destroy;
		m_api.defer_enable = defer_enable;
		m_api.defer_free = defer_free;

		m_api.userdata = this;
	}

	return &m_api;
}

// A PulseAudio io event: one dispatch source for reading and one for writing.
//
// PulseAudio frees the event for its socket and creates a new one whenever the socket is both readable
// and writable, which is all the time. Cancelling dispatch sources and creating new ones for the same
// descriptor that often makes the event machinery deliver events for sources that are gone, so freed
// events are parked (with their sources suspended) and reused for the same descriptor.
struct dual_source
{
	PADispatchMainLoop* loop;
	dispatch_source_t sourceRead, sourceWrite;
	bool readResumed = false, writeResumed = false;
	pa_io_event_cb_t callback = nullptr;
	pa_io_event_destroy_cb_t destroy = nullptr;
	void* userdata = nullptr;
	int fd;
	// what the descriptor referred to, to tell whether a parked event still applies to it
	dev_t dev = 0;
	ino_t ino = 0;
	// held by PulseAudio, rather than parked
	bool inUse = false;
	// in the loop's cache; other ones are destroyed when freed
	bool cached = false;
};

static void dual_identify(int fd, dev_t* dev, ino_t* ino)
{
	struct stat st;
	if (fstat(fd, &st) == 0)
	{
		*dev = st.st_dev;
		*ino = st.st_ino;
	}
}

// Delivers the events PulseAudio asked for, and none while the event is parked
static void dual_set_events(dual_source* dual, pa_io_event_flags_t events)
{
	const bool read = dual->inUse && (events & (PA_IO_EVENT_INPUT | PA_IO_EVENT_ERROR | PA_IO_EVENT_HANGUP));
	const bool write = dual->inUse && (events & PA_IO_EVENT_OUTPUT);

	if (read != dual->readResumed)
	{
		if (read)
			dispatch_resume(dual->sourceRead);
		else
			dispatch_suspend(dual->sourceRead);
		dual->readResumed = read;
	}
	if (write != dual->writeResumed)
	{
		if (write)
			dispatch_resume(dual->sourceWrite);
		else
			dispatch_suspend(dual->sourceWrite);
		dual->writeResumed = write;
	}
}

static dual_source* dual_create(PADispatchMainLoop* loop, dispatch_queue_t q, int fd)
{
	dual_source* dual = new dual_source;

	dual->loop = loop;
	dual->fd = fd;
	dual_identify(fd, &dual->dev, &dual->ino);
	// sources start out suspended
	dual->sourceRead = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, q);
	dual->sourceWrite = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, q);

	dispatch_source_set_event_handler(dual->sourceRead, ^{
		if (dual->inUse)
			dual->callback(loop->getAPI(), reinterpret_cast<pa_io_event*>(dual), fd, PA_IO_EVENT_INPUT, dual->userdata);
	});

	dispatch_source_set_event_handler(dual->sourceWrite, ^{
		if (dual->inUse)
			dual->callback(loop->getAPI(), reinterpret_cast<pa_io_event*>(dual), fd, PA_IO_EVENT_OUTPUT, dual->userdata);
	});

	dispatch_source_set_cancel_handler(dual->sourceWrite, ^{
		delete dual;
	});

	return dual;
}

static void dual_destroy(dual_source* dual)
{
	dual->inUse = false;

	// a suspended source doesn't get to its cancellation
	if (!dual->readResumed)
		dispatch_resume(dual->sourceRead);
	dispatch_source_cancel(dual->sourceRead);
	dispatch_release(dual->sourceRead);

	if (!dual->writeResumed)
		dispatch_resume(dual->sourceWrite);
	dispatch_source_cancel(dual->sourceWrite);
	dispatch_release(dual->sourceWrite);

	// dual is freed in the cancel handler
}

pa_io_event* PADispatchMainLoop::io_new(pa_mainloop_api *a, int fd, pa_io_event_flags_t events, pa_io_event_cb_t cb, void *userdata)
{
	PADispatchMainLoop* This = static_cast<PADispatchMainLoop*>(a->userdata);
	dual_source* dual = nullptr;

	auto it = This->m_ioSources.find(fd);
	if (it != This->m_ioSources.end() && !it->second->inUse)
	{
		dev_t dev = 0;
		ino_t ino = 0;
		dual_identify(fd, &dev, &ino);

		if (it->second->dev == dev && it->second->ino == ino)
			dual = it->second;
		else
		{
			// the descriptor was closed, and its number was reused
			dual_destroy(it->second);
			This->m_ioSources.erase(it);
		}
	}

	if (!dual)
	{
		dual = dual_create(This, This->m_queue, fd);
		// one event per descriptor gets reused; should there be more, the others are not
		dual->cached = This->m_ioSources.emplace(fd, dual).second;
	}

	dual->callback = cb;
	dual->userdata = userdata;
	dual->destroy = nullptr;
	dual->inUse = true;
	dual_set_events(dual, events);

	return reinterpret_cast<pa_io_event*>(dual);
}

void PADispatchMainLoop::io_enable(pa_io_event *e, pa_io_event_flags_t events)
{
	dual_set_events(reinterpret_cast<dual_source*>(e), events);
}

void PADispatchMainLoop::io_free(pa_io_event *e)
{
	dual_source* dual = reinterpret_cast<dual_source*>(e);
	PADispatchMainLoop* loop = dual->loop;
	pa_io_event_destroy_cb_t destroy = dual->destroy;
	void* userdata = dual->userdata;

	dual->inUse = false;
	dual->destroy = nullptr;

	if (dual->cached)
		dual_set_events(dual, PA_IO_EVENT_NULL);
	else
		dual_destroy(dual);

	if (destroy)
		destroy(loop->getAPI(), e, userdata);
}

void PADispatchMainLoop::io_set_destroy(pa_io_event *e, pa_io_event_destroy_cb_t cb)
{
	dual_source* dual = reinterpret_cast<dual_source*>(e);
	dual->destroy = cb;
}

struct linux_timeval
{
	unsigned long tv_sec;
	long tv_usec;
};

struct pa_timer
{
	dispatch_source_t source;
	void* userdata;
	struct timespec when;
	struct linux_timeval tv;
	pa_time_event_destroy_cb_t destroy = nullptr;
};

pa_time_event *PADispatchMainLoop::time_new(pa_mainloop_api *a, const struct timeval *tv, pa_time_event_cb_t cb, void *userdata)
{
	const linux_timeval* real_tv = reinterpret_cast<const linux_timeval*>(tv);
	PADispatchMainLoop* This = static_cast<PADispatchMainLoop*>(a->userdata);
	dispatch_queue_t q = This->m_queue;

	pa_timer* timer = new pa_timer;

	timer->userdata = userdata;

	timer->source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);

	timer->when.tv_sec = real_tv->tv_sec;
	timer->when.tv_nsec = real_tv->tv_usec * 1000; // convert to ns
	timer->tv = *real_tv;

	// std::cout << "PADispatchMainLoop::time_new(), sec=" << real_tv->tv_sec << ", usec=" << real_tv->tv_usec << std::endl;

	dispatch_source_set_timer(timer->source, dispatch_walltime(&timer->when, 0), 0, 0);

	dispatch_source_set_event_handler(timer->source, ^{
		// std::cout << "PADispatchMainLoop::time_new(): fired\n";
		cb(This->getAPI(), reinterpret_cast<pa_time_event*>(timer), reinterpret_cast<const struct timeval *>(&timer->tv), timer->userdata);
	});
	dispatch_source_set_cancel_handler(timer->source, ^{
		if (timer->destroy)
			timer->destroy(This->getAPI(), reinterpret_cast<pa_time_event*>(timer), timer->userdata);
		delete timer;
	});

	dispatch_resume(timer->source);

	return reinterpret_cast<pa_time_event*>(timer);
}

void PADispatchMainLoop::time_restart(pa_time_event *e, const struct timeval *tv)
{
	const linux_timeval* real_tv = reinterpret_cast<const linux_timeval*>(tv);
	pa_timer* timer = reinterpret_cast<pa_timer*>(e);

	timer->when.tv_sec = real_tv->tv_sec;
	timer->when.tv_nsec = real_tv->tv_usec * 1000; // convert to ns
	timer->tv = *real_tv;

	// std::cout << "PADispatchMainLoop::time_restart(), sec=" << real_tv->tv_sec << ", usec=" << real_tv->tv_usec << std::endl;

	dispatch_source_set_timer(timer->source, dispatch_walltime(&timer->when, 0), 0, 0);
}

void PADispatchMainLoop::time_set_destroy(pa_time_event *e, pa_time_event_destroy_cb_t cb)
{
	pa_timer* timer = reinterpret_cast<pa_timer*>(e);

	timer->destroy = cb;
}

void PADispatchMainLoop::time_free(pa_time_event *e)
{
	pa_timer* timer = reinterpret_cast<pa_timer*>(e);

	// std::cout << "PADispatchMainLoop::time_free()\n";

	dispatch_source_cancel(timer->source);
	dispatch_release(timer->source);
}

struct defer_event
{
	bool active = true;
	void* userdata;
	pa_defer_event_cb_t callback;
	pa_defer_event_destroy_cb_t destroy = nullptr;
	PADispatchMainLoop* loop;
};

void PADispatchMainLoop::defer_event_fire(void* context)
{
	defer_event* ev = static_cast<defer_event*>(context);
	if (ev->active)
	{
		pa_mainloop_api* a = ev->loop->getAPI();
		dispatch_queue_t q = static_cast<PADispatchMainLoop*>(a->userdata)->m_queue;

		// std::cout << "PADispatchMainLoop::defer_event_fire(): with userdata=" << ev->userdata << std::endl;

		ev->callback(a, static_cast<pa_defer_event*>(context), ev->userdata);

		if (ev->active)
			dispatch_async_f(q, context, defer_event_fire);
	}
}

pa_defer_event *PADispatchMainLoop::defer_new(pa_mainloop_api *a, pa_defer_event_cb_t cb, void *userdata)
{
	// std::cout << "PADispatchMainLoop::defer_new(): with userdata=" << userdata << std::endl;
	PADispatchMainLoop* This = static_cast<PADispatchMainLoop*>(a->userdata);
	dispatch_queue_t q = This->m_queue;
	defer_event* e = new defer_event;

	e->loop = This;
	e->userdata = userdata;
	e->callback = cb;

	dispatch_async_f(q, e, defer_event_fire);

	return reinterpret_cast<pa_defer_event*>(e);
}

void PADispatchMainLoop::defer_set_destroy(pa_defer_event *e, pa_defer_event_destroy_cb_t cb)
{
	defer_event* ev = reinterpret_cast<defer_event*>(e);

	ev->destroy = cb;
}

void PADispatchMainLoop::defer_enable(pa_defer_event *e, int b)
{
	defer_event* ev = reinterpret_cast<defer_event*>(e);
	dispatch_queue_t q = ev->loop->m_queue;

	// std::cout << "PADispatchMainLoop::defer_enable(): with userdata=" << ev->userdata << ", enable=" << b << std::endl;

	if (!ev->active && b)
		dispatch_async_f(q, e, defer_event_fire);
	ev->active = !!b;
}

void PADispatchMainLoop::defer_free(pa_defer_event *e)
{
	defer_event* ev = reinterpret_cast<defer_event*>(e);
	dispatch_queue_t q = ev->loop->m_queue;

	// std::cout << "PADispatchMainLoop::defer_free(): with userdata=" << ev->userdata << std::endl;

	ev->active = false;

	dispatch_async(q, ^{
		if (ev->destroy)
			ev->destroy(ev->loop->getAPI(), e, ev->userdata);
		delete ev;
	});
}
