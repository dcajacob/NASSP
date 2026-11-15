// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#if defined(NASSP_NATIVE_LINUX)
#include "NativeVesselAPI.h"
#include "Production/FlightKeys.h"
#include "Production/NativeRenderApi.h"
#include <strings.h>

// Scalar identities used by the original SDK declarations.
using UINT = oapi::UInt;
using DWORD = oapi::UInt32;
// The native oapiBlt already uses the source surface's configured colour key.
inline constexpr auto NasspPanelBlitKey = SURF_NO_CK;

inline int strnicmp(const char* left, const char* right, std::size_t count)
{
	return strncasecmp(left, right, count);
}

inline int stricmp(const char* left, const char* right)
{
	return strcasecmp(left, right);
}
#else
#include "Orbitersdk.h"
inline constexpr auto NasspPanelBlitKey = SURF_PREDEF_CK;
#endif
