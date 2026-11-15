// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#if defined(NASSP_NATIVE_LINUX)
#include <cstddef>
#include <cstdio>

// The original RTCC display code uses the bounded MSVC overloads throughout.
template <class... Args>
int sprintf_s(char* buffer, std::size_t capacity, const char* format, Args... arguments)
{
	if (!buffer || capacity == 0 || !format) return -1;
	const int written = std::snprintf(buffer, capacity, format, arguments...);
	if (written < 0 || static_cast<std::size_t>(written) >= capacity) {
		buffer[0] = '\0';
		return -1;
	}
	return written;
}

template <std::size_t N, class... Args>
int sprintf_s(char (&buffer)[N], const char* format, Args... arguments)
{
	return sprintf_s(buffer, N, format, arguments...);
}
#endif
