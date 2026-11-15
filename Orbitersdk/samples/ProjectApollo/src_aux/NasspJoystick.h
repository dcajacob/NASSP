// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <array>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>
#include <linux/joystick.h>

namespace nassp {

class Joystick {
public:
	enum class Axis { X, Y, Z, RX, RY, RZ, Slider0, Slider1 };

	static std::vector<Joystick> OpenDevices(const std::filesystem::path& directory = "/dev/input");
	Joystick(Joystick&& other) noexcept;
	Joystick(const Joystick&) = delete;
	~Joystick();

	const std::string& Name() const { return name; }
	bool Poll();
	std::optional<int> Position(Axis axis) const;
	std::optional<int> Hat(int index, bool vertical) const;
	std::optional<bool> Button(int index) const;
	std::optional<int> Slider(int index) const;
	int LongitudinalPosition(int rotationAxis, bool nativeZ, int slider = -1) const;
	void DetectLegacyAxes(int& rotationAxis, int& nativeZ, int& hat) const;

private:
	explicit Joystick(const std::filesystem::path& path);
	void Close();
	std::optional<int> PositionForCode(int code) const;

	int descriptor = -1;
	std::string name;
	std::array<int, ABS_CNT> axisIndices;
	std::array<int, 2> sliderCodes{{-1, -1}};
	std::vector<int> positions;
	std::vector<bool> buttons;
};

} // namespace nassp
