// SPDX-License-Identifier: GPL-2.0-or-later
#include "NasspCsmBitmap.h"

#include "Production/NativeGraphics.h"
#include "resource.h"

#include <stdexcept>

namespace nassp {

SURFHANDLE LoadCsmBitmap(int resourceId)
{
	static constexpr struct {
		int id;
		const char* path;
	} bitmaps[] = {
#include "nassp-csm-bitmaps.inc"
	};
	for (const auto& bitmap : bitmaps) {
		if (bitmap.id != resourceId) continue;
		if (const auto surface = oapiLoadSurfaceEx(bitmap.path, OAPISURFACE_NOMIPMAPS))
			return surface;
		throw std::runtime_error(std::string("Cannot load NASSP panel bitmap ") + bitmap.path);
	}
	throw std::runtime_error("Unknown NASSP panel bitmap ID " + std::to_string(resourceId));
}

void SetCsmSurfaceColourKey(SURFHANDLE surface, DWORD colour)
{
	if (auto* graphics = orbiter::production::GetNativeRenderContext().graphics)
		if (surface) graphics->clbkSetSurfaceColourKey(surface, colour);
}

} // namespace nassp
