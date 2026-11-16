/***************************************************************************
This file is part of Project Apollo - NASSP
Copyright 2018

Apollo RTCC MFD OAPI Module

Project Apollo is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

Project Apollo is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Project Apollo; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

See http://nassp.sourceforge.net/license/ for more details.

**************************************************************************/

#define STRICT
#define ORBITER_MODULE

#include "NasspOrbiterSdk.h"
#include "ApolloRTCCMFD.h"
#include "ARoapiModule.h"
#if defined(NASSP_NATIVE_LINUX)
#include "Production/NativeApolloRtccMfd.h"
#include "Production/NativeAbi.h"
#include "Production/ModuleBootstrap.h"
#include <memory>
#endif

//
// ==============================================================
// Pointers to Global variables in Apollo RTCC
// ==============================================================
//

extern ARoapiModule *g_coreMod;
extern ARCore *GCoreData[32];
extern VESSEL *GCoreVessel[32];
extern AR_GlobalData g_GlobalData;
extern AR_GCore *g_SC;
extern int nGutsUsed;
extern int g_MFDmode;

//
// Static globals for this compilation file
//

static char name[] = "Apollo RTCC MFD";

//
// ==============================================================
// Orbiter DLL API interface
// ==============================================================
//

#if defined(NASSP_NATIVE_LINUX)
oapi::CockpitMessageResult ARoapiModule::MsgProc(UINT msg, UINT mfd,
    oapi::CockpitUnsignedParam dimensions, oapi::CockpitSignedParam vessel)
{
    if (msg != OAPI_MSG_MFD_OPENED) return 0;
    return reinterpret_cast<oapi::CockpitMessageResult>(new ApolloRTCCMFD(
        dimensions & 0xffff, (dimensions >> 16) & 0xffff, reinterpret_cast<VESSEL*>(vessel), mfd));
}

namespace {
orbiter::production::NativeApolloRtccMfdApi callbacks = {
    sizeof(orbiter::production::NativeApolloRtccMfdApi),
    [](double simt, double simdt, double mjd) { g_coreMod->clbkPreStep(simt, simdt, mjd); },
    [](OBJHANDLE vessel) { g_coreMod->clbkDeleteVessel(vessel); },
    [] { g_coreMod->clbkSimulationEnd(); }
};

int ORBITER_NATIVE_CALL Initialize(const OrbiterNativeHost *host, void **instance,
    char *error, std::uint32_t capacity) noexcept
{
    if (!host || host->struct_size != sizeof(*host) || !host->context || !instance || g_coreMod) {
        std::snprintf(error, capacity, "Invalid or repeated Apollo RTCC MFD initialization");
        return 1;
    }
    try {
        auto core = std::make_unique<ARoapiModule>();
        MFDMODESPECEX spec{};
        spec.name = name;
        spec.key = OAPI_KEY_W;
        spec.msgproc = ARoapiModule::MsgProc;
        g_MFDmode = oapiRegisterMFDMode(spec);
        g_coreMod = core.release();
        *instance = &callbacks;
        return 0;
    } catch (...) {
        std::snprintf(error, capacity, "Cannot register Apollo RTCC MFD");
        return 1;
    }
}

void ORBITER_NATIVE_CALL Shutdown(void*) noexcept
{
    oapiUnregisterMFDMode(g_MFDmode);
    delete g_coreMod;
    g_coreMod = nullptr;
    g_MFDmode = 0;
}

const OrbiterNativeModuleDescriptor descriptor = {
    sizeof(OrbiterNativeModuleDescriptor), ORBITER_NATIVE_BOOTSTRAP_VERSION,
    sizeof(void*), ORBITER_NATIVE_PLUGIN, "NASSP Apollo RTCC MFD",
    ORBITER_NATIVE_SDK_BUILD, ORBITER_NATIVE_CPP_ABI, Initialize, Shutdown
};
}

extern "C" ORBITER_NATIVE_EXPORT const OrbiterNativeModuleDescriptor* ORBITER_NATIVE_CALL
OrbiterNativeQuery(std::uint32_t version) noexcept
{
    return version == ORBITER_NATIVE_BOOTSTRAP_VERSION ? &descriptor : nullptr;
}
#else
DLLCLBK void InitModule(HINSTANCE hDLL) {          // Called by Orbiter when module selected in the Launchpad
	g_coreMod = new ARoapiModule(hDLL);           // Declare a single root class instance for ApolloRTCCMFD for this simulation run


	MFDMODESPECEX spec;
	spec.name = name;
	spec.key = OAPI_KEY_W;                            // MFD mode selection key (change as needed)
	spec.msgproc = ARoapiModule::MsgProc;         // MFD mode callback function
	spec.context = NULL;
	g_MFDmode = oapiRegisterMFDMode(spec);           // Tell Orbiter we are an MFD
	oapiRegisterModule(g_coreMod);                    // Register this whole module with Orbiter
	nGutsUsed = 0;
}

DLLCLBK void ExitModule(HINSTANCE hDLL) {          // Called by Orbiter when module deselected in the Launchpad
	oapiUnregisterMFDMode(g_MFDmode);                // Unregister use as an MFD. Note - don't kill the g_coreMod module (Orbiter does this)
	g_coreMod = NULL;
	nGutsUsed = 0;
}

OAPI_MSGTYPE ARoapiModule::MsgProc(UINT msg, UINT mfd, WPARAM wparam, LPARAM lparam) {  // Message parser, handling MFD open requests
	switch (msg) {
	case OAPI_MSG_MFD_OPENED:
		return (OAPI_MSGTYPE)(new ApolloRTCCMFD(LOWORD(wparam), HIWORD(wparam), (VESSEL*)lparam, mfd));    // Open an ephemeral RTCC instance each time we make a new RTCC MFD, plus F8, etc/ 
	}
	return 0;
}

ARoapiModule::ARoapiModule(HINSTANCE hDLL) : oapi::Module(hDLL) {}
ARoapiModule::~ARoapiModule() {}

void ARoapiModule::clbkSimulationStart(RenderMode mode) {}

#endif

void ARoapiModule::clbkSimulationEnd() {                                      // When we exit sim back to Launchpad, make sure we tidy things up properly
	for (int i = 0;i<nGutsUsed;i++) {
		delete GCoreData[i];
		GCoreVessel[i] = NULL;
	}
	nGutsUsed = 0;
	if (g_SC)
	{
		delete g_SC;
		g_SC = 0;
	}
	return;
}
void ARoapiModule::clbkPreStep(double simt, double simdt, double mjd) {      // Called on each iteration of the calc engine (more often than the MFD Update
	for (int i = 0;i<nGutsUsed;i++) {
		GCoreData[i]->MinorCycle(simt, simdt, mjd);
	}
	return;
}

#if !defined(NASSP_NATIVE_LINUX)
void ARoapiModule::clbkPostStep(double simt, double simdt, double mjd) {}
#endif

void ARoapiModule::clbkDeleteVessel(OBJHANDLE hVessel) {                     // Tidy up when a vessel is deleted (stops clbkPreStep calling a dead vessel)
	VESSEL *vessel = oapiGetVesselInterface(hVessel);
	for (int i = 0;i<nGutsUsed;i++) {
		if (GCoreVessel[i] == vessel) {
			delete GCoreData[i];
			for (int j = i; j<nGutsUsed - 1; j++) {
				GCoreVessel[j] = GCoreVessel[j + 1];
				GCoreData[j] = GCoreData[j + 1];
			}
			nGutsUsed--;
			break;
		}
	}
}

#if !defined(NASSP_NATIVE_LINUX)
DLLCLBK void opcSaveState(FILEHANDLE scn)
{
	g_GlobalData.SaveState(scn);
}

DLLCLBK void opcLoadState(FILEHANDLE scn)
{
	g_GlobalData.LoadState(scn);
}
#endif
