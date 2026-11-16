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
extern "C" {
#include <lua/lua.h>
#include <lua/lauxlib.h>
}
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
int SendCommandUplink(MCC &control, const char *uplink)
{
	const int pendingSize = control.uplink_size;
	unsigned char pending[sizeof(control.uplink_data)];
	memcpy(pending, control.uplink_data, pendingSize);
	control.uplink_size = 0;
	control.pushCMCUplinkString(uplink);
	const int sent = control.CM_uplink_buffer();
	memcpy(control.uplink_data, pending, pendingSize);
	control.uplink_size = pendingSize;
	return sent;
}

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
	if (mcc)
	{
		delete mcc;
		mcc = NULL;
	}
	if (rtcc)
	{
		delete rtcc;
		rtcc = NULL;
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
#if defined(NASSP_NATIVE_LINUX)
	if (msgid == VMSG_LUAINSTANCE) {
		auto *state = static_cast<lua_State *>(context);
		if (luaL_newmetatable(state, "VESSEL.MCC")) {
			static const luaL_Reg methods[] = {
				{"calculate_tei", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					const double lead = luaL_checknumber(lua, 2);
					const double longitude = luaL_checknumber(lua, 3);
					const int returnSpeed = luaL_optint(lua, 4, 1);
					luaL_argcheck(lua, std::isfinite(lead) && lead >= 0.0, 2, "lead time must be nonnegative");
					luaL_argcheck(lua, std::isfinite(longitude) && fabs(longitude) <= 180.0, 3, "longitude out of range");
					luaL_argcheck(lua, returnSpeed >= 0 && returnSpeed <= 2, 4, "return speed must be 0, 1, or 2");
					const OBJHANDLE handle = oapiGetVesselByName(center.CSMName);
					auto *vehicle = handle ? oapiGetVesselInterface(handle) : nullptr;
					if (!vehicle || vehicle->GetGravityRef() != oapiGetGbodyByName("Moon"))
						return luaL_error(lua, "The tracked CSM must be in lunar orbit");

					RTEMoonOpt options{};
					options.vessel = vehicle;
					options.EntryLng = longitude * RAD;
					options.returnspeed = returnSpeed;
					auto &rtcc = *center.rtcc;
					options.RV_MCC = rtcc.coast(rtcc.StateVectorCalc(vehicle), lead);
					EntryResults result{};
					rtcc.RTEMoonTargeting(&options, &result);
					if (!result.solutionfound) {
						lua_pushnil(lua);
						return 1;
					}
					lua_pushnumber(lua, result.P30TIG);
					lua_pushnumber(lua, result.dV_LVLH.x);
					lua_pushnumber(lua, result.dV_LVLH.y);
					lua_pushnumber(lua, result.dV_LVLH.z);
					lua_pushnumber(lua, result.GET400K);
					lua_pushnumber(lua, result.latitude * DEG);
					lua_pushnumber(lua, result.longitude * DEG);
					lua_pushnumber(lua, result.ReA * DEG);
					return 8;
				}},
				{"calculate_earth_corridor", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					const double lead = luaL_checknumber(lua, 2);
					luaL_argcheck(lua, std::isfinite(lead) && lead >= 0.0, 2, "lead time must be nonnegative");
					const OBJHANDLE handle = oapiGetVesselByName(center.CSMName);
					auto *vehicle = handle ? oapiGetVesselInterface(handle) : nullptr;
					if (!vehicle)
						return luaL_error(lua, "The tracked CSM is unavailable");

					auto &rtcc = *center.rtcc;
					EntryOpt options{};
					options.vessel = vehicle;
					options.RV_MCC = rtcc.StateVectorCalc(vehicle);
					if (options.RV_MCC.gravref != oapiGetGbodyByName("Earth"))
						return luaL_error(lua, "The tracked CSM must be in Earth's sphere of influence");
					const double now = rtcc.GETfromGMT(OrbMech::GETfromMJD(options.RV_MCC.MJD, rtcc.GetGMTBase()));
					options.TIGguess = now + lead;
					options.type = 3; // Flight corridor update
					options.entrylongmanual = true;
					options.enginetype = RTCC_ENGINETYPE_CSMSPS;

					EntryResults result{};
					rtcc.EntryTargeting(options, result);
					if (!result.solutionfound || result.GET400K <= result.P30TIG) {
						lua_pushnil(lua);
						return 1;
					}

					const VECTOR3 down = unit(result.sv_preburn.R * -1.0);
					const VECTOR3 normal = unit(crossp(result.sv_preburn.V, result.sv_preburn.R));
					const VECTOR3 forward = crossp(normal, down);
					const auto &dv = result.dV_LVLH;
					const VECTOR3 brcs = forward * dv.x + normal * dv.y + down * dv.z;
					const VECTOR3 ecliptic = mul(OrbMech::tmat(rtcc.SystemParameters.MAT_J2000_BRCS), brcs);
					for (double value : {result.P30TIG, dv.x, dv.y, dv.z, result.GET400K,
					                     result.ReA * DEG, now, ecliptic.x, ecliptic.z, ecliptic.y}) {
						lua_pushnumber(lua, value);
					}
					return 10;
				}},
				{"calculate_earth_corridor_along", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					const double lead = luaL_checknumber(lua, 2);
					const VECTOR3 direction = _V(luaL_checknumber(lua, 3), luaL_checknumber(lua, 4), luaL_checknumber(lua, 5));
					const double target = luaL_optnumber(lua, 6, -6.5) * RAD;
					luaL_argcheck(lua, std::isfinite(lead) && lead > 0.0, 2, "lead time must be positive");
					const double norm = length(direction);
					luaL_argcheck(lua, std::isfinite(norm) && norm > 0.0, 3, "invalid thrust direction");
					luaL_argcheck(lua, std::isfinite(target) && target < 0.0 && target > -PI05, 6, "invalid entry angle");
					const OBJHANDLE handle = oapiGetVesselByName(center.CSMName);
					auto *vehicle = handle ? oapiGetVesselInterface(handle) : nullptr;
					if (!vehicle)
						return luaL_error(lua, "The tracked CSM is unavailable");
					auto &rtcc = *center.rtcc;
					const SV state = rtcc.StateVectorCalc(vehicle);
					const auto earth = oapiGetGbodyByName("Earth");
					if (state.gravref != earth)
						return luaL_error(lua, "The tracked CSM must be in Earth's sphere of influence");

					const SV atBurn = rtcc.coast(state, lead);
					const auto seed = rtcc.ConvertSVtoEphemData(atBurn);
					const double now = rtcc.GETfromGMT(seed.GMT) - lead;
					const VECTOR3 axis = mul(rtcc.SystemParameters.MAT_J2000_BRCS, _V(direction.x, direction.z, direction.y) / norm);
					const double radius = oapiGetSize(earth) + 400000.0 * 0.3048;
					auto entryAngle = [&](double magnitude, EphemerisData &entry) {
						auto post = seed;
						post.V = post.V + axis * magnitude;
						int stop = 0;
						rtcc.PMMCEN(post, 0.0, 5.0 * 86400.0, 3, radius, 1.0, entry, stop);
						const double sine = dotp(unit(entry.R), unit(entry.V));
						if (entry.RBI != BODY_EARTH || fabs(length(entry.R) - radius) > 100.0 || sine >= 0.0)
							return 0.0;
						return asin(sine);
					};

					EphemerisData entry;
					double lower = 0.0;
					double upper = 2.0;
					if (entryAngle(lower, entry) >= target)
						return luaL_error(lua, "An outward correction is unnecessary");
					while (upper < 64.0 && entryAngle(upper, entry) < target)
						upper *= 2.0;
					if (entryAngle(upper, entry) < target)
						return luaL_error(lua, "No corridor solution along the supplied direction");
					for (int i = 0; i < 17; ++i) {
						const double trial = (lower + upper) * 0.5;
						if (entryAngle(trial, entry) < target)
							lower = trial;
						else
							upper = trial;
					}
					const double magnitude = (lower + upper) * 0.5;
					const double angle = entryAngle(magnitude, entry);
					if (fabs(angle - target) > 0.01 * RAD)
						return luaL_error(lua, "The entry corridor solution did not converge");

					double tig = 0.0;
					VECTOR3 dv{};
					rtcc.PoweredFlightProcessor(atBurn, 0.0, RTCC_ENGINETYPE_CSMSPS, 0.0, axis * magnitude, false, tig, dv);
					const VECTOR3 inertial = direction * (magnitude / norm);
					for (double value : {tig, dv.x, dv.y, dv.z, rtcc.GETfromGMT(entry.GMT), angle * DEG,
					                     now, inertial.x, inertial.y, inertial.z}) {
						lua_pushnumber(lua, value);
					}
					return 10;
				}},
				{"uplink_entry", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					const OBJHANDLE handle = oapiGetVesselByName(center.CSMName);
					auto *vehicle = handle ? oapiGetVesselInterface(handle) : nullptr;
					if (!vehicle || !center.mcc || !center.mcc->cm)
						return luaL_error(lua, "The tracked CSM or its uplink is unavailable");
					auto &rtcc = *center.rtcc;
					const SV state = rtcc.StateVectorCalc(vehicle);
					const auto ephemeris = rtcc.ConvertSVtoEphemData(state);
					EntryResults result{};
					if (state.gravref != oapiGetGbodyByName("Earth") ||
						rtcc.EntryUpdateCalc(ephemeris, rtcc.PZREAP.RRBIAS, true, result) ||
						!std::isfinite(result.latitude) || !std::isfinite(result.longitude)) {
						return luaL_error(lua, "RTCC could not predict the entry target");
					}

					char uplink[512];
					char target[128];
					rtcc.AGCStateVectorUpdate(uplink, state, true);
					rtcc.CMCEntryUpdate(target, result.latitude, result.longitude);
					strcat(uplink, target);
					const int sent = SendCommandUplink(*center.mcc, uplink);
					if (sent <= 0)
						return luaL_error(lua, "The CMC entry uplink was rejected");

					for (double value : {static_cast<double>(sent), result.latitude * DEG, result.longitude * DEG,
					                     result.GET400K, result.ReA * DEG, rtcc.GETfromGMT(ephemeris.GMT)}) {
						lua_pushnumber(lua, value);
					}
					return 6;
				}},
				{"uplink_p30", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					const double tig = luaL_checknumber(lua, 2);
					const VECTOR3 deltaV = _V(luaL_checknumber(lua, 3), luaL_checknumber(lua, 4), luaL_checknumber(lua, 5));
					luaL_argcheck(lua, std::isfinite(tig) && tig >= 0.0, 2, "invalid ignition GET");
					luaL_argcheck(lua, std::isfinite(deltaV.x) && std::isfinite(deltaV.y) && std::isfinite(deltaV.z), 3, "invalid delta-V vector");
					if (!center.mcc || !center.mcc->cm)
						return luaL_error(lua, "CMC uplink is unavailable");
					const OBJHANDLE handle = oapiGetVesselByName(center.CSMName);
					auto *vehicle = handle ? oapiGetVesselInterface(handle) : nullptr;
					if (!vehicle)
						return luaL_error(lua, "The tracked CSM is unavailable");
					char uplink[512];
					char target[128];
					center.rtcc->AGCStateVectorUpdate(uplink, center.rtcc->StateVectorCalc(vehicle), true);
					center.rtcc->CMCExternalDeltaVUpdate(target, tig, deltaV);
					strcat(uplink, target);
					const int sent = SendCommandUplink(*center.mcc, uplink);
					if (sent <= 0)
						return luaL_error(lua, "CMC uplink queue rejected the request");
					lua_pushinteger(lua, sent);
					lua_createtable(lua, 10, 0);
					for (int i = 0; i < 10; ++i) {
						lua_pushinteger(lua, center.rtcc->CZAXTRDV.Octals[i]);
						lua_rawseti(lua, -2, i + 1);
					}
					return 2;
				}},
				{"uplink_cmc_platform_reference", [](lua_State *lua) {
					auto **slot = static_cast<VESSEL **>(luaL_checkudata(lua, 1, "VESSEL.MCC"));
					auto &center = *static_cast<MCCVessel *>(*slot);
					if (!center.mcc || !center.mcc->cm)
						return luaL_error(lua, "CMC uplink is unavailable");
					luaL_checktype(lua, 2, LUA_TTABLE);
					MATRIX3 stableToOrbiter;
					for (int i = 0; i < 9; ++i) {
						lua_rawgeti(lua, 2, i + 1);
						stableToOrbiter.data[i] = luaL_checknumber(lua, -1);
						lua_pop(lua, 1);
						luaL_argcheck(lua, std::isfinite(stableToOrbiter.data[i]) && fabs(stableToOrbiter.data[i]) <= 1.000001, 2, "invalid reference matrix element");
					}
					const auto &m = stableToOrbiter;
					const MATRIX3 stableToEcliptic = _M(m.m11, m.m12, m.m13, m.m31, m.m32, m.m33, m.m21, m.m22, m.m23);
					const MATRIX3 refsmmat = OrbMech::tmat(mul(center.rtcc->SystemParameters.MAT_J2000_BRCS, stableToEcliptic));
					char uplink[256];
					center.rtcc->AGCREFSMMATUpdate(uplink, refsmmat, true);
					const int sent = SendCommandUplink(*center.mcc, uplink);
					if (sent <= 0)
						return luaL_error(lua, "CMC reference uplink failed");
					lua_pushinteger(lua, sent);
					return 1;
				}},
				{nullptr, nullptr}
			};
			lua_newtable(state);
			luaL_register(state, nullptr, methods);
			lua_newtable(state);
			luaL_getmetatable(state, "VESSEL.vtable");
			lua_setfield(state, -2, "__index");
			lua_setmetatable(state, -2);
			lua_setfield(state, -2, "__index");
		}
		lua_setmetatable(state, -2);
		return 0;
	}
#endif
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