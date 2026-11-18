-- Replay the Apollo 7 SPS-3 crew procedure from the preserved pre-burn save.
-- Ullage uses the normal THC, leaving SCS pitch/yaw stabilization available.
-- DIRECT ULLAGE bypasses those axes and is used only for the ignition interlock.
local timeToIgnition = 1342.097088597482

local ship = vessel.get_focusinterface()
local target = assert(oapi.get_objhandle("AS-205-S4BSTG"))
local report = assert(io.open("sps3-scs.csv", "w"))
report:write("relative_to_tig,marker,sps_mass,altitude,orbital_speed,wx,wy,wz,tacc,target_range,periapsis,apoapsis,uplink\n")
local qualification=assert(io.open("sps3-qualification.csv","w"))
qualification:write("relative_to_tig,marker,ems_fps,sps_level,attitude_error_deg,rate_deg_s,ullage_impulse_m_s\n")
local engine,maximum
for i=0,ship:get_thrustercount()-1 do
    local thruster=ship:get_thrusterhandle(i)
    local thrust=ship:get_thrustermax0(thruster)
    if not maximum or thrust>maximum then engine,maximum=thruster,thrust end
end
assert(maximum>80000,"SPS engine was not found")
local ullageAttitude
local ullageImpulse=0
local function attitudeError()
    if not ullageAttitude then return 0 end
    return math.deg(math.acos(math.max(-1,math.min(1,
        vec.dotp(ullageAttitude,ship:globalrot(_V(0,0,1)))))))
end
local sps
for i = 0, ship:get_propellantcount()-1 do
    local tank = ship:get_propellanthandle(i)
    if not sps or ship:get_propellantmaxmass(tank) > ship:get_propellantmaxmass(sps) then
        sps = tank
    end
end
assert(sps and ship:get_propellantmaxmass(sps) > 1000, "SPS tank was not found")

local function reportState(marker)
    local w = ship:get_angvel()
    local earth = ship:get_gravityref()
    local radius = oapi.get_size(earth)
    local _,orbit = ship:get_elementsex(earth)
    local range = vec.length(vec.sub(oapi.get_globalpos(target),ship:get_globalpos()))
    report:write(string.format("%.3f,%s,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%.2f,%.3f,%.3f,%.3f,%d\n",
        oapi.get_simtime()-timeToIgnition, marker, ship:get_propellantmass(sps),
        ship:get_altitude(1), vec.length(ship:get_relativevel(ship:get_gravityref())),
        w.x, w.y, w.z, oapi.get_tacc(), range, orbit.PeD-radius, orbit.ApD-radius, ship:get_agcuplinkstatus()))
    report:flush()
    qualification:write(string.format("%.6f,%s,%.3f,%.8f,%.6f,%.6f,%.8f\n",
        oapi.get_simtime()-timeToIgnition,marker,ship:get_panelswitch("EMSDvDisplay"),
        ship:get_thrusterlevel(engine),attitudeError(),math.deg(vec.length(w)),ullageImpulse))
    qualification:flush()
end

local function set(name, value)
    ship:set_panelswitch(name, value)
    assert(ship:get_panelswitch(name) == value, "Switch did not move: "..name)
end

local function press(name, marker)
    reportState(marker)
    -- Momentary DSKY keys can spring back during the switch callback.
    ship:set_panelswitch(name, 1, true)
    proc.wait_simdt(0.5)
    ship:set_panelswitch(name, 0)
end

local function at(seconds, marker)
    local duration = timeToIgnition+seconds-oapi.get_simtime()
    if duration > 0 then proc.wait_simdt(duration) end
    reportState(marker)
end

local function waitPrompt(verb,noun,seconds)
    local limit = oapi.get_simtime()+seconds
    while ship:get_agcerasable(2,1)~=verb or ship:get_agcerasable(2,2)~=noun do
        assert(oapi.get_simtime()<limit,"Missing DSKY V"..verb.." N"..noun)
        proc.wait_simdt(.25)
    end
end
proc.wait_simdt(2)
reportState("original_sps3_target")
waitPrompt(50,18,30)
set("SCContSwitch",1)
set("CMCModeSwitch",2)
press("DskySwitchProg","start_maneuver")
waitPrompt(6,18,20)
-- R60 shows V06 N18 during the slew and returns to flashing V50 N18.
-- ENTER accepts the attitude. PRO at that point commands another slew.
local settleLimit=timeToIgnition-385
while ship:get_agcerasable(2,1)~=50 or ship:get_agcerasable(2,2)~=18 do
    local remaining=settleLimit-oapi.get_simtime()
    assert(remaining>0,"SPS-3 attitude maneuver did not finish before the gimbal checks")
    oapi.set_tacc(remaining>100 and 2.5 or 1)
    proc.wait_simdt(math.min(1,remaining))
end
oapi.set_tacc(1)
proc.wait_simdt(2)
press("DskySwitchEnter","r60_attitude_accepted")
waitPrompt(50,25,35)
reportState("gimbal_option")
oapi.set_tacc(8)
at(-335, "slow_to_normal_time")
oapi.set_tacc(1)
at(-330, "gimbal_preparation")
for _,axis in ipairs({"Pitch","Yaw"}) do
    for _,bus in ipairs({"A","B"}) do set(axis.."Bat"..bus.."CircuitBraker",1) end
end
for _,axis in ipairs({"Roll","Pitch","Yaw"}) do set("ManualAtt"..axis.."Switch",1) end
set("AttDeadbandSwitch",0)
for name,bus in pairs({
    PitchA3Switch=0,PitchC3Switch=2,PitchA4Switch=2,PitchC4Switch=0,
    YawB3Switch=2,YawD3Switch=0,YawB4Switch=0,YawD4Switch=2,
    AcRollA1Switch=0,AcRollC1Switch=2,AcRollA2Switch=0,AcRollC2Switch=2,
    BdRollB1Switch=1,BdRollB2Switch=1,BdRollD1Switch=1,BdRollD2Switch=1,
}) do set(name,bus) end
set("TVCServoPower1Switch", 2)
set("TVCServoPower2Switch", 0)
set("TVCGimbalDrivePitchSwitch", 1)
set("TVCGimbalDriveYawSwitch", 1)
set("MainBusTieBatAcSwitch", 2)
set("MainBusTieBatBcSwitch", 2)
set("TransContrSwitch", 1)
set("THCRotary", 1)
local motors = {"Pitch1Switch", "Yaw1Switch", "Pitch2Switch", "Yaw2Switch"}
for _, name in ipairs(motors) do set(name, 2) end
proc.wait_simdt(1)
for _, name in ipairs(motors) do set(name, 1) end
set("BMAGRollSwitch",1)
set("BMAGPitchSwitch",1)
set("BMAGYawSwitch",1)
waitPrompt(50,25,15)
press("DskySwitchProg","perform_gimbal_test")
waitPrompt(6,40,55)
at(-285, "gimbal_test_complete")
oapi.set_tacc(4)
at(-126, "slow_to_arm")
oapi.set_tacc(1)

at(-120,"arm_sps")
set("dVThrust1Switch",1)
set("dVThrust2Switch",1)
oapi.set_tacc(4)
at(-61,"setup_scs")
oapi.set_tacc(1)
-- Apollo 7 SPS-3 checklist, T-1:00. LOW rate applies until ignition.
set("LimitCycleSwitch",0)
set("AttRateSwitch",0)
set("SCContSwitch",0)
set("SCSTvcPitchSwitch",2)
set("SCSTvcYawSwitch",2)
set("EMSFunctionSwitch",2)
set("EMSDvDisplay",2319)
set("EMSFunctionSwitch",1)
set("EMSModeSwitch",2)
at(-30,"ullage")
ullageAttitude=ship:globalrot(_V(0,0,1))
local priorRcsMode=ship:get_rcsmode()
ship:set_rcsmode(2)
local previous=oapi.get_simtime()
while oapi.get_simtime()<timeToIgnition-15 do
    -- The default native key mapping drives the THC forward in translation mode.
    oapi.simulateimmediatekey(OAPI_KEY.NUMPAD6)
    proc.wait_frames(1)
    local now=oapi.get_simtime()
    ullageImpulse=ullageImpulse+ship:get_thrustvector().z*(now-previous)/ship:get_mass()
    previous=now
end
-- Release the one-frame key and allow the normal control path to see neutral.
proc.wait_frames(2)
ship:set_rcsmode(priorRcsMode)
reportState("ullage_complete")
assert(ullageImpulse>1 and ullageImpulse<3,"THC ullage impulse outside four-jet bounds")
assert(attitudeError()<2,"Ullage lost the burn attitude")
at(-5,"cmc_monitoring")
press("DskySwitchEnter","cmc_residual_display")
at(0,"manual_ignition")
assert(attitudeError()<2,"Spacecraft is not pointing at the SPS-3 burn attitude")
local originalMass=ship:get_propellantmass(sps)
ship:set_panelswitch("DirectUllageButton",1,true)
ship:set_panelswitch("ThrustOnButton",1,true)
proc.wait_simdt(1)
set("ThrustOnButton",0)
set("DirectUllageButton",0)
set("AttRateSwitch",1)
for i=1,60 do
    reportState("burn_watch")
    proc.wait_simdt(1)
end
local used=originalMass-ship:get_propellantmass(sps)
reportState("ems_cutoff_check")
assert(used>100 and used<600,"SPS-3 fuel use outside expected bounds")
assert(ship:get_panelswitch("EMSDvDisplay")<=0,"EMS did not reach the cutoff setting")
assert(ship:get_thrusterlevel(engine)==0,"EMS did not stop the SPS engine")
local cutoffMass=ship:get_propellantmass(sps)
proc.wait_simdt(2)
assert(math.abs(ship:get_propellantmass(sps)-cutoffMass)<.005,"SPS continued burning after EMS cutoff")
set("dVThrust1Switch",0)
set("dVThrust2Switch",0)
local earth=ship:get_gravityref()
local radius=oapi.get_size(earth)
local _,orbit=ship:get_elementsex(earth)
local stable=vec.length(ship:get_angvel())<.08
local orbitMatches=math.abs(orbit.PeD-radius-175838.224380)<15000 and math.abs(orbit.ApD-radius-309338.700664)<15000
assert(stable,"SPS-3 attitude did not settle after cutoff")
assert(orbitMatches,"SPS-3 missed the original maneuver PAD orbit limits")
reportState("sps3_completed")
qualification:close()
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
