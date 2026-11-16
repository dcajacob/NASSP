/***************************************************************************
  This file is part of Project Apollo - NASSP
  Copyright 2024

  ORBITER vessel module: EASEP LR3

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

#define ORBITER_MODULE

  // To force Orbitersdk.h to use <fstream> in any compiler version
#pragma include_alias( <fstream.h>, <fstream> )
#include "NasspOrbiterSdk.h"
#if defined(NASSP_NATIVE_LINUX)
#include "Production/NativeVesselFactory.h"
#endif
#include "EasepLR3.h"

#if !defined(NASSP_NATIVE_LINUX)
static 	int refcount = 0;
#endif
static MESHHANDLE hEasepLR3;

EasepLR3::EasepLR3(OBJHANDLE hObj, int fmodel) : VESSEL2(hObj, fmodel)
{
	hMaster = hObj;
}

EasepLR3::~EasepLR3()
{

}

void EasepLR3::clbkSetClassCaps(FILEHANDLE cfg)
{
	SetEmptyMass(2);
	SetSize(1);
	SetPMI(_V(15, 15, 15));

	SetSurfaceFrictionCoeff(0.5, 0.5);
	SetRotDrag(_V(0, 0, 0));
	SetCW(0, 0, 0, 0);
	SetPitchMomentScale(0);
	SetYawMomentScale(0);
	SetLiftCoeffFunc(0);

	ClearMeshes();
	ClearExhaustRefs();
	ClearAttExhaustRefs();
	VECTOR3 mesh_adjust = _V(0.0, 0.0, 0.0);
	AddMesh(hEasepLR3, &mesh_adjust);
	SetMeshVisibilityMode(0, MESHVIS_ALWAYS);

	double x_target = -0.001;
	double stiffness = (-1) * (2 * G) / (3 * x_target);
	double damping = 0.9 * (2 * sqrt(2 * stiffness));
	for (int i = 0; i < ntdvtx; i++)
	{
		tdvtx[i].damping = damping;
		tdvtx[i].mu = 3;
		tdvtx[i].mu_lng = 3;
		tdvtx[i].stiffness = stiffness;
	}
	tdvtx[0].pos.x = cos(30 * RAD) * 0.1;
	tdvtx[0].pos.y = -0.774;
	tdvtx[0].pos.z = -sin(30 * RAD) * 0.1;
	tdvtx[1].pos.x = 0;
	tdvtx[1].pos.y = -0.774;
	tdvtx[1].pos.z = 1.55;
	tdvtx[2].pos.x = -cos(30 * RAD) * 0.1;
	tdvtx[2].pos.y = -0.774;
	tdvtx[2].pos.z = -sin(30 * RAD) * 0.1;

	SetTouchdownPoints(tdvtx, ntdvtx);

	spawned = true;
}

void EasepLR3::DoFirstTimestep()
{
	if (spawned) {
		RotateToFaceEarth(GetEarthPos());
		spawned = false;
	}
}

VECTOR3 EasepLR3::GetEarthPos()
{
	VECTOR3 rearth;
	VECTOR3 rearthinv;
	VECTOR3 rearthloc;
	GetGlobalPos(rearth);
	rearthinv = _V(-rearth.x, -rearth.y, -rearth.z);
	Global2Local(rearthinv, rearthloc);

	return rearthloc;
}

void EasepLR3::RotateToFaceEarth(VECTOR3 rearthloc)
{
	double heading = 0;
	oapiGetHeading(hMaster, &heading);
	if (heading >= PI2) heading -= PI2; //range always 0-2pi
	else if (heading < 0) heading += PI2;

	double earthangle = atan2(rearthloc.x, rearthloc.z); //current angle of earth on XY plane relative to z axis

	heading += earthangle;

	VESSELSTATUS vs1;
	GetStatus(vs1);
	vs1.vdata[0].z = heading;
	DefSetState(&vs1);
}

void EasepLR3::clbkPreStep(double SimT, double SimDT, double mjd)
{
	if (spawned) {
		DoFirstTimestep();
		return;
	}
}

void EasepLR3::clbkPostCreation()
{

}

void EasepLR3::clbkLoadStateEx(FILEHANDLE scn, void* vs)
{
	char* line;
	while (oapiReadScenario_nextline(scn, line))
	{
		ParseScenarioLineEx(line, vs);
	}

	spawned = false;
}

void EasepLR3::clbkVisualCreated(VISHANDLE vis, int refcount)
{

}

void EasepLR3::clbkVisualDestroyed(VISHANDLE vis, int refcount)
{

}

#if defined(NASSP_NATIVE_LINUX)
namespace {
VESSEL *Create(OBJHANDLE vessel, int flightmodel)
{
	hEasepLR3 = oapiLoadMeshGlobal("ProjectApollo/EASEP_LR3");
	return new EasepLR3(vessel, flightmodel);
}

void Destroy(VESSEL *vessel)
{
	delete static_cast<EasepLR3 *>(vessel);
}

using Factory = orbiter::native::VesselFactory<Create, Destroy>;
const OrbiterNativeModuleDescriptor descriptor = {
	sizeof(OrbiterNativeModuleDescriptor), ORBITER_NATIVE_BOOTSTRAP_VERSION,
	sizeof(void*), ORBITER_NATIVE_VESSEL, "Apollo EASEP laser retroreflector",
	ORBITER_NATIVE_SDK_BUILD, ORBITER_NATIVE_CPP_ABI, Factory::initialize, Factory::shutdown
};
}

extern "C" ORBITER_NATIVE_EXPORT const OrbiterNativeModuleDescriptor* ORBITER_NATIVE_CALL
OrbiterNativeQuery(std::uint32_t version) noexcept
{
	return version == ORBITER_NATIVE_BOOTSTRAP_VERSION ? &descriptor : nullptr;
}
#else
DLLCLBK VESSEL* ovcInit(OBJHANDLE hvessel, int flightmodel)
{
	if (!refcount++) {
		hEasepLR3 = oapiLoadMeshGlobal("ProjectApollo/EASEP_LR3");
	}

	return new EasepLR3(hvessel, flightmodel);
}

DLLCLBK void ovcExit(VESSEL* vessel)
{
	EasepLR3* sv = (EasepLR3*)vessel;

	if (sv)
		delete sv;
}

DLLCLBK void InitModule(HINSTANCE hModule)
{

}
#endif
