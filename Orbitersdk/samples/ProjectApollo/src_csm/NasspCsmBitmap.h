// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "NasspOrbiterSdk.h"

namespace nassp {

SURFHANDLE LoadCsmBitmap(int resourceId);
void SetCsmSurfaceColourKey(SURFHANDLE surface, DWORD colour);

void InitSaturnPanelResources();
void ReleaseSaturnPanelResources();

} // namespace nassp
