// Native Orbiter interfaces used by the original VesselBuilder flight code.
#pragma once
#include "NativeVesselAPI.h"
#include "Production/FlightKeys.h"
#include "Production/NativeInterpreterSdk.h"
#include "Production/NativeRenderApi.h"
#include "Production/NativeGraphics.h"
#include "Production/ResourceResolver.h"
#include <algorithm>
#include <cstdarg>
#include <cmath>
#include <fstream>
#include <strings.h>

using UINT = oapi::UInt;
using DWORD = oapi::UInt32;
using WORD = oapi::UInt16;
inline constexpr int VMSG_USER = 0x1000;

inline bool oapiIsVessel(OBJHANDLE object)
{
    return object && oapiGetObjectType(object) == OBJTP_VESSEL;
}

inline int _strnicmp(const char* left, const char* right, std::size_t count)
{
    return strncasecmp(left, right, count);
}

template<std::size_t N, typename... Args>
int sprintf_s(char (&buffer)[N], const char* format, Args... args)
{
    return std::snprintf(buffer, N, format, args...);
}

template<typename... Args>
int sprintf_s(char* buffer, std::size_t size, const char* format, Args... args)
{
    return std::snprintf(buffer, size, format, args...);
}

#define _ARRAYSIZE(array) std::size(array)
