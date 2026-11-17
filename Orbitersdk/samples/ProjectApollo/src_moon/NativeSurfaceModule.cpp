// Native entry point shared by the separately loaded EVA and surface vessels.
#include "Production/NativeVesselFactory.h"
#include "OrbiterNativeBuild.h"

VESSEL* CreateSurfaceVessel(OBJHANDLE vessel, int flightmodel);
void DestroySurfaceVessel(VESSEL* vessel);

namespace {
using Factory = orbiter::native::VesselFactory<CreateSurfaceVessel, DestroySurfaceVessel>;
const OrbiterNativeModuleDescriptor descriptor = {
    sizeof(OrbiterNativeModuleDescriptor), ORBITER_NATIVE_BOOTSTRAP_VERSION,
    sizeof(void*), ORBITER_NATIVE_VESSEL, NASSP_NATIVE_SURFACE_MODULE,
    ORBITER_NATIVE_SDK_BUILD, ORBITER_NATIVE_CPP_ABI, Factory::initialize, Factory::shutdown
};
}

extern "C" ORBITER_NATIVE_EXPORT const OrbiterNativeModuleDescriptor* ORBITER_NATIVE_CALL
OrbiterNativeQuery(std::uint32_t version) noexcept
{
    return version == ORBITER_NATIVE_BOOTSTRAP_VERSION ? &descriptor : nullptr;
}
