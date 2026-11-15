/****************************************************************************
  This file is part of Project Apollo - NASSP

  Mission Control Center Vessel

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

#include "mccvessel.h"
#include "rtcc.h"
#include "mcc.h"
#include "paCBGmessageID.h"
#include "Mission.h"

#include "nasspdefs.h"

#if defined(NASSP_NATIVE_LINUX)
#include "Production/NativeVesselFactory.h"
#define MCC_VESSEL_CALLBACK static
#else
#define ORBITER_MODULE
#define MCC_VESSEL_CALLBACK DLLCLBK
#endif

static int refcount = 0;

#if !defined(NASSP_NATIVE_LINUX)

DLLCLBK void InitModule(HINSTANCE hDLL)
{
}

DLLCLBK void ExitModule(HINSTANCE hDLL)
{
}
#endif

MCC_VESSEL_CALLBACK VESSEL* ovcInit(OBJHANDLE hVessel, int iFlightModel)
{
	if (!refcount++) {
		LoadMeshes();
	}

	return new MCCVessel(hVessel, iFlightModel);
}

MCC_VESSEL_CALLBACK void ovcExit(VESSEL* pVessel)
{
    --refcount;

	delete static_cast<MCCVessel*>(pVessel);
}

#undef MCC_VESSEL_CALLBACK

#if defined(NASSP_NATIVE_LINUX)
namespace {
using MCCFactory = orbiter::native::VesselFactory<ovcInit, ovcExit>;
const OrbiterNativeModuleDescriptor mccModule = {
	sizeof(OrbiterNativeModuleDescriptor), ORBITER_NATIVE_BOOTSTRAP_VERSION,
	sizeof(void*), ORBITER_NATIVE_VESSEL, "NASSP Mission Control Center",
	ORBITER_NATIVE_SDK_BUILD, ORBITER_NATIVE_CPP_ABI,
	MCCFactory::initialize, MCCFactory::shutdown
};
}

extern "C" ORBITER_NATIVE_EXPORT const OrbiterNativeModuleDescriptor* ORBITER_NATIVE_CALL
OrbiterNativeQuery(std::uint32_t version) noexcept
{
	return version == ORBITER_NATIVE_BOOTSTRAP_VERSION ? &mccModule : nullptr;
}
#endif

MCCVessel::MCCVessel(OBJHANDLE hVessel, int flightmodel) : VESSEL4(hVessel, flightmodel)
{
	//Vessel data
	CSMName[0] = 0;
	LEMName[0] = 0;
	LVName[0] = 0;
	rtcc = new RTCC();
	mcc = NULL;

	//Mission File
	InitMissionManagementMemory();
	pMission = paGetDefaultMission();
}

MCCVessel::~MCCVessel()
{
#if defined(NASSP_NATIVE_LINUX)
	if (mfdButtonFont) oapiReleaseFont(mfdButtonFont);
#endif
	if (rtcc)
	{
		delete rtcc;
		rtcc = NULL;
	}
	if (mcc)
	{
		delete mcc;
		mcc = NULL;
	}
}

void MCCVessel::clbkPreStep(double simt, double simdt, double mjd)
{
	// Update Ground Data
	if (mcc) mcc->TimeStep(simdt);
	if (rtcc) rtcc->Timestep(simt, simdt, mjd);
}

int MCCVessel::clbkGeneric(int msgid, int prm, void* context)
{
	if (!mcc) { return 0; }

	if (msgid == paCBGmessageID::messageID::RF_PROPERTIES) {

		RFCALC_RFProperties *RFtemp = (RFCALC_RFProperties*)context;

		if (prm == paCBGmessageID::parameterID::GetCM || prm == paCBGmessageID::parameterID::GetLM)
		{
			int slot;

			if (prm == paCBGmessageID::parameterID::GetCM)
			{
				slot = MCC::TrackingSlot::SlotCM;
			}
			else
			{
				slot = MCC::TrackingSlot::SlotLM;
			}

			RFtemp->GlobalPosition = (mcc->TransmittingGroundStationVector[slot]);

			if (mcc->GroundStations[mcc->TransmittingGroundStation[slot]].SBandAntenna & GSSA_26METER) {
				RFtemp->Gain = pow(10.0, (50.0 / 10.0));
				RFtemp->Power = 20.0E3;
			}
			else if (mcc->GroundStations[mcc->TransmittingGroundStation[slot]].SBandAntenna & GSSA_9METER) {
				RFtemp->Gain = pow(10.0, (43.0 / 10.0));
				RFtemp->Power = 10E3;
			}
			else if (mcc->GroundStations[mcc->TransmittingGroundStation[slot]].SBandAntenna & GSSA_3PT7METER) {
				RFtemp->Gain = pow(10.0, (37.0 / 10.0));
				RFtemp->Power = 22.9;
			}
			else {
				RFtemp->Gain = 1.0;
				RFtemp->Power = 0.0;
			}

			return 1;
		}
	}

	return 0;

}

void MCCVessel::clbkSaveState(FILEHANDLE scn)
{
	VESSEL4::clbkSaveState(scn);

	if (strMission.length() > 0) oapiWriteScenario_string(scn, "MISSION", (char*)strMission.c_str());
	if (CSMName[0])
		oapiWriteScenario_string(scn, "CSMNAME", CSMName);

	if (LVName[0])
		oapiWriteScenario_string(scn, "LVNAME", LVName);

	if (LEMName[0])
		oapiWriteScenario_string(scn, "LEMNAME", LEMName);

	if (mcc) mcc->SaveState(scn);
	if (rtcc) rtcc->SaveState(scn);
}

void MCCVessel::clbkLoadStateEx(FILEHANDLE scn, void *status)
{
	char *line;

	while (oapiReadScenario_nextline(scn, line)) {
		if (!strnicmp(line, "MISSIONTRACKING", 15)) {
			int i;
			sscanf(line + 15, "%d", &i);
			if (i)
			{
				CreateMCC();
				mcc->enableMissionTracking();
			}
		}
		else if (!strnicmp(line, "MISSION ", 8))
		{
			CreateMCC();
			strMission = line + 8;
			LoadMissionFile();
			SetConfiguration();
		}
		else if (!strnicmp(line, "CSMNAME", 7))
		{
			strncpy(CSMName, line + 8, 64);
		}
		else if (!strnicmp(line, "LVNAME", 6))
		{
			strncpy(LVName, line + 7, 64);
		}
		else if (!strnicmp(line, "LEMNAME", 7))
		{
			strncpy(LEMName, line + 8, 64);
		}
		else if (!strnicmp(line, MCC_START_STRING, sizeof(MCC_START_STRING)))
		{
			CreateMCC();
			if (mcc) mcc->LoadState(scn);
		}
		else if (!strnicmp(line, RTCC_START_STRING, sizeof(RTCC_START_STRING))) {
			if (rtcc) rtcc->LoadState(scn);
		}
		else ParseScenarioLineEx(line, status);
	}
}

void MCCVessel::clbkSetClassCaps(FILEHANDLE cfg)
{
	LoadVC();
}

void MCCVessel::clbkPostCreation()
{
	//CSM
	if (CSMName[0])
	{
		if (mcc) mcc->SetCSM(CSMName);
	}
	//S-IVB
	if (LVName[0])
	{
		if (mcc) mcc->SetLV(LVName);
	}
	//LEM
	if (LEMName[0])
	{
		if (mcc) mcc->SetLM(LEMName);
	}
	if (rtcc) rtcc->clbkPostCreation();
}

void MCCVessel::CreateMCC()
{
	if (mcc == NULL)
	{
		mcc = new MCC(rtcc);
	}
}

void MCCVessel::LoadMissionFile()
{
	pMission->LoadMission(strMission);
}

void MCCVessel::SetConfiguration()
{
	if (mcc)
	{
		//Additional ground station
		std::vector<mission::GroundStationData> data = pMission->GetGroundStationData();

		if (data.size() != 0)
		{
			GroundStation temp;

			for (unsigned i = 0; i < data.size(); i++)
			{
				strcpy(temp.Name, data[i].Name);
				strcpy(temp.Code, data[i].Code);
				temp.Position[0] = data[i].Position[0];
				temp.Position[1] = data[i].Position[1];
				temp.Active = data[i].Active;
				temp.TrackingCaps = data[i].TrackingCaps;
				temp.USBCaps = data[i].USBCaps;
				temp.SBandAntenna = data[i].SBandAntenna;
				temp.TelemetryCaps = data[i].TelemetryCaps;
				temp.CommCaps = data[i].CommCaps;
				temp.HasRadar = data[i].HasRadar;
				temp.HasAcqAid = data[i].HasAcqAid;
				temp.DownTlmCaps = data[i].DownTlmCaps;
				temp.UpTlmCaps = data[i].UpTlmCaps;
				temp.StationType = data[i].StationType;
				temp.StationPurpose = data[i].StationPurpose;
				temp.AOS[0] = temp.AOS[1] = 0;

				mcc->SetGroundStation(data[i].Num, temp);
			}
		}

		//Overload ground station position
		std::vector<mission::GroundStationPosition> data2 = pMission->GetGroundStationPosition();

		if (data2.size() != 0)
		{
			for (unsigned i = 0; i < data2.size(); i++)
			{
				if (mcc->GroundStations.size() > (unsigned)data2[i].Num)
				{
					mcc->GroundStations[data2[i].Num].Active = true; //Assumes we want to set the station active, if we are loading new positions
					mcc->GroundStations[data2[i].Num].Position[0] = data2[i].Position[0];
					mcc->GroundStations[data2[i].Num].Position[1] = data2[i].Position[1];
				}
			}
		}

		//Set stations active/inactive
		std::vector<mission::GroundStationActive> data3 = pMission->GetGroundStationActive();

		if (data3.size() != 0)
		{
			for (unsigned i = 0; i < data3.size(); i++)
			{
				if (mcc->GroundStations.size() > (unsigned)data3[i].Num)
				{
					mcc->GroundStations[data3[i].Num].Active = data3[i].Active;
				}
			}
		}
	}
}