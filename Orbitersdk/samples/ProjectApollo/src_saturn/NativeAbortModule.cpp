#include "Production/NativeVesselFactory.h"
#include "OrbiterNativeBuild.h"

VESSEL* CreateAbortVessel(OBJHANDLE vessel, int flightmodel);
void DestroyAbortVessel(VESSEL* vessel);

namespace {
using Factory = orbiter::native::VesselFactory<CreateAbortVessel, DestroyAbortVessel>;
const OrbiterNativeModuleDescriptor descriptor = {
    sizeof(OrbiterNativeModuleDescriptor), ORBITER_NATIVE_BOOTSTRAP_VERSION,
    sizeof(void*), ORBITER_NATIVE_VESSEL, NASSP_NATIVE_ABORT_MODULE,
    ORBITER_NATIVE_SDK_BUILD, ORBITER_NATIVE_CPP_ABI, Factory::initialize, Factory::shutdown
};
}

extern "C" ORBITER_NATIVE_EXPORT const OrbiterNativeModuleDescriptor* ORBITER_NATIVE_CALL
OrbiterNativeQuery(std::uint32_t version) noexcept
{
    return version == ORBITER_NATIVE_BOOTSTRAP_VERSION ? &descriptor : nullptr;
}
