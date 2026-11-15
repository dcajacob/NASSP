// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "NasspOrbiterSdk.h"
#include "soundlib.h"
#include <memory>

class NasspNativeSound {
public:
	explicit NasspNativeSound(VESSEL* vessel);
	~NasspNativeSound();

	bool IsPresent() const;
	bool LoadWav(int id, const char* filename, EXTENDEDPLAY mode);
	bool PlayWav(int id, bool loop, float volume);
	bool StopWav(int id);
	bool IsWavPlaying(int id);
	void UpdateView();

private:
	struct State;
	std::unique_ptr<State> state;
};
