// SPDX-License-Identifier: GPL-2.0-or-later

#include "NasspNativeSound.h"
#include "Production/NativeGraphics.h"
#include "Production/ResourceResolver.h"

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_ENCODING
#include "miniaudio.h"

#include <algorithm>
#include <cmath>
#include <mutex>
#include <unordered_map>

namespace {
struct AudioEngine {
	ma_engine engine{};
	const bool ready = ma_engine_init(nullptr, &engine) == MA_SUCCESS;

	~AudioEngine()
	{
		if (ready) ma_engine_uninit(&engine);
	}
};

std::shared_ptr<AudioEngine> GetAudioEngine()
{
	static std::mutex mutex;
	static std::weak_ptr<AudioEngine> cache;
	const std::lock_guard<std::mutex> lock(mutex);
	auto engine = cache.lock();
	if (!engine) {
		engine = std::make_shared<AudioEngine>();
		cache = engine;
	}
	return engine;
}

struct Wav {
	ma_sound sound{};
	bool loaded = false;
	float volume = 0.0f;
	EXTENDEDPLAY mode;

	Wav(ma_engine& engine, const char* path, EXTENDEDPLAY mode) : mode(mode)
	{
		loaded = ma_sound_init_from_file(&engine, path, MA_SOUND_FLAG_NO_SPATIALIZATION,
			nullptr, nullptr, &sound) == MA_SUCCESS;
	}
	~Wav()
	{
		if (loaded) ma_sound_uninit(&sound);
	}
};
}

struct NasspNativeSound::State {
	explicit State(VESSEL* vessel) : vessel(vessel), audio(GetAudioEngine()) {}

	VESSEL* vessel;
	std::shared_ptr<AudioEngine> audio;
	std::mutex mutex;
	std::unordered_map<int, std::unique_ptr<Wav>> wavs;
	bool focus = false;
	bool cockpit = false;
	double pressure = 0.0;
	double distance = 0.0;

	void UpdateVolume(Wav& wav)
	{
		float volume = wav.volume;
		double audibleDistance = 0.0;
		switch (wav.mode) {
		case DEFAULT:
			break;
		case RADIO_SOUND:
			if (!focus) volume = 0.0f;
			break;
		case INTERNAL_ONLY:
			if (!cockpit) volume = 0.0f;
			break;
		case BOTHVIEW_FADED_CLOSE:
			audibleDistance = 20.0;
			break;
		case BOTHVIEW_FADED_MEDIUM:
			audibleDistance = 50.0;
			break;
		case BOTHVIEW_FADED_FAR:
			audibleDistance = 125.0;
			break;
		case EXTERNAL_ONLY_FADED_CLOSE:
		case EXTERNAL_ONLY_FADED_MEDIUM:
		case EXTERNAL_ONLY_FADED_FAR:
			volume = cockpit ? 0.0f : volume * pressure;
			break;
		}
		if (audibleDistance > 0.0 && !cockpit) {
			const double ratio = audibleDistance / std::max(distance, audibleDistance);
			volume *= ratio * ratio * pressure;
			if (volume < 0.04f) volume = 0.0f;
		}
		ma_sound_set_volume(&wav.sound, volume);
	}
};

NasspNativeSound::NasspNativeSound(VESSEL* vessel) : state(std::make_unique<State>(vessel)) {}
NasspNativeSound::~NasspNativeSound() = default;

bool NasspNativeSound::IsPresent() const
{
	return state->audio->ready;
}

bool NasspNativeSound::LoadWav(int id, const char* filename, EXTENDEDPLAY mode)
{
	const auto* files = orbiter::production::GetNativeRenderContext().programFiles;
	if (!IsPresent() || !files || !files->Contains(filename)) return false;
	const auto path = files->Resolve(filename);

	const std::lock_guard<std::mutex> lock(state->mutex);
	auto wav = std::make_unique<Wav>(state->audio->engine, path.c_str(), mode);
	if (!wav->loaded) return false;
	state->wavs[id] = std::move(wav);
	return true;
}

bool NasspNativeSound::PlayWav(int id, bool loop, float volume)
{
	const std::lock_guard<std::mutex> lock(state->mutex);
	const auto entry = state->wavs.find(id);
	if (entry == state->wavs.end()) return false;

	Wav& wav = *entry->second;
	wav.volume = volume;
	state->UpdateVolume(wav);
	ma_sound_set_looping(&wav.sound, loop ? MA_TRUE : MA_FALSE);
	if (ma_sound_at_end(&wav.sound) && ma_sound_seek_to_pcm_frame(&wav.sound, 0) != MA_SUCCESS)
		return false;
	return ma_sound_start(&wav.sound) == MA_SUCCESS;
}

bool NasspNativeSound::StopWav(int id)
{
	const std::lock_guard<std::mutex> lock(state->mutex);
	const auto entry = state->wavs.find(id);
	if (entry == state->wavs.end()) return false;
	auto& sound = entry->second->sound;
	return ma_sound_stop(&sound) == MA_SUCCESS && ma_sound_seek_to_pcm_frame(&sound, 0) == MA_SUCCESS;
}

bool NasspNativeSound::IsWavPlaying(int id)
{
	const std::lock_guard<std::mutex> lock(state->mutex);
	const auto entry = state->wavs.find(id);
	return entry != state->wavs.end() && ma_sound_is_playing(&entry->second->sound);
}

void NasspNativeSound::UpdateView()
{
	if (!IsPresent()) return;
	const std::lock_guard<std::mutex> lock(state->mutex);
	state->focus = state->vessel->GetHandle() == oapiGetFocusObject();
	state->cockpit = state->focus && oapiCameraInternal();
	state->pressure = std::clamp(state->vessel->GetAtmPressure() / 10132.5, 0.0, 1.0);
	VECTOR3 vessel{}, camera{};
	state->vessel->GetGlobalPos(vessel);
	oapiCameraGlobalPos(&camera);
	state->distance = length(vessel - camera);
	for (const auto& entry : state->wavs)
		state->UpdateVolume(*entry.second);
}
