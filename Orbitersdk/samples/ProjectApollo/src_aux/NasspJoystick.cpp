// SPDX-License-Identifier: GPL-2.0-or-later
#include "NasspJoystick.h"

#include <algorithm>
#include <cerrno>
#include <charconv>
#include <cstdint>
#include <utility>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace nassp {

std::vector<Joystick> Joystick::OpenDevices(const std::filesystem::path& directory)
{
	std::vector<std::pair<unsigned, std::filesystem::path>> paths;
	std::error_code error;
	for (auto entry = std::filesystem::directory_iterator(directory, error);
	     !error && entry != std::filesystem::directory_iterator{}; entry.increment(error)) {
		const auto filename = entry->path().filename().string();
		if (filename.compare(0, 2, "js") != 0 || filename.size() == 2) continue;
		unsigned number;
		const auto parsed = std::from_chars(filename.data() + 2, filename.data() + filename.size(), number);
		if (parsed.ec == std::errc{} && parsed.ptr == filename.data() + filename.size())
			paths.emplace_back(number, entry->path());
	}
	std::sort(paths.begin(), paths.end());
	std::vector<Joystick> devices;
	for (const auto& entry : paths) {
		Joystick device(entry.second);
		if (device.Poll()) devices.push_back(std::move(device));
	}
	return devices;
}

Joystick::Joystick(const std::filesystem::path& path)
{
	axisIndices.fill(-1);
	descriptor = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (descriptor < 0) return;

	std::uint8_t axisCount, buttonCount;
	std::array<std::uint8_t, ABS_CNT> axisCodes{};
	if (ioctl(descriptor, JSIOCGAXES, &axisCount) < 0 ||
	    ioctl(descriptor, JSIOCGBUTTONS, &buttonCount) < 0 ||
	    ioctl(descriptor, JSIOCGAXMAP, axisCodes.data()) < 0 || axisCount > axisCodes.size()) {
		Close();
		return;
	}
	char deviceName[128]{};
	if (ioctl(descriptor, JSIOCGNAME(sizeof(deviceName) - 1), deviceName) > 0)
		name = deviceName;
	if (name.empty()) name = path.filename().string();

	positions.resize(axisCount, 32768);
	buttons.resize(buttonCount);
	for (std::size_t i = 0; i < axisCount; ++i) {
		const auto code = axisCodes[i];
		if (code < axisIndices.size()) axisIndices[code] = static_cast<int>(i);
	}
	constexpr int sliderCandidates[] = {ABS_THROTTLE, ABS_RUDDER, ABS_WHEEL, ABS_GAS, ABS_BRAKE};
	std::size_t sliders = 0;
	for (const int code : sliderCandidates) {
		if (axisIndices[code] >= 0) sliderCodes[sliders++] = code;
		if (sliders == sliderCodes.size()) break;
	}
}

Joystick::Joystick(Joystick&& other) noexcept
	: descriptor(std::exchange(other.descriptor, -1)), name(std::move(other.name)),
	  axisIndices(other.axisIndices), sliderCodes(other.sliderCodes),
	  positions(std::move(other.positions)), buttons(std::move(other.buttons))
{
}

Joystick::~Joystick()
{
	Close();
}

void Joystick::Close()
{
	if (descriptor >= 0) close(std::exchange(descriptor, -1));
}

bool Joystick::Poll()
{
	while (descriptor >= 0) {
		js_event event{};
		const auto size = read(descriptor, &event, sizeof(event));
		if (size == sizeof(event)) {
			const int type = event.type & ~JS_EVENT_INIT;
			if (type == JS_EVENT_AXIS && event.number < positions.size()) {
				const int level = static_cast<int>(event.value);
				positions[event.number] = level <= -32767 ? 0 : 32768 + level;
			} else if (type == JS_EVENT_BUTTON && event.number < buttons.size()) {
				buttons[event.number] = event.value != 0;
			}
			continue;
		}
		if (size < 0 && errno == EINTR) continue;
		if (size < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return true;
		Close();
	}
	return false;
}

std::optional<int> Joystick::PositionForCode(int code) const
{
	if (descriptor < 0 || code < 0 || axisIndices[code] < 0) return {};
	return positions[axisIndices[code]];
}

std::optional<int> Joystick::Position(Axis axis) const
{
	const int codes[] = {ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ, sliderCodes[0], sliderCodes[1]};
	return PositionForCode(codes[static_cast<int>(axis)]);
}

std::optional<int> Joystick::Hat(int index, bool vertical) const
{
	if (index < 0 || index > 3) return {};
	return PositionForCode(ABS_HAT0X + 2 * index + static_cast<int>(vertical));
}

std::optional<bool> Joystick::Button(int index) const
{
	if (descriptor < 0 || index < 0 || static_cast<std::size_t>(index) >= buttons.size()) return {};
	return buttons[index];
}

std::optional<int> Joystick::Slider(int index) const
{
	if (index < 0 || index >= static_cast<int>(sliderCodes.size())) return {};
	return PositionForCode(sliderCodes[index]);
}

int Joystick::LongitudinalPosition(int rotationAxis, bool nativeZ, int slider) const
{
	constexpr Axis axes[] = {Axis::RX, Axis::RY, Axis::RZ};
	if (rotationAxis >= 0 && rotationAxis < 3)
		return Position(axes[rotationAxis]).value_or(32768);
	if (nativeZ) return Position(Axis::Z).value_or(32768);
	return Slider(slider).value_or(32768);
}

void Joystick::DetectLegacyAxes(int& rotationAxis, int& nativeZ, int& hat) const
{
	if (Position(Axis::Z)) nativeZ = 1;
	if (Position(Axis::RZ)) rotationAxis = 2;
	if (Hat(0, true)) hat = 0;
}

} // namespace nassp
