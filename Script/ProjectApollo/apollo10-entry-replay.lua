-- Apollo 10 entry replay for the verified pre-separation checkpoint.
-- The 125-degree bank is specific to this trajectory.
local cmJetThrust = 413.7 -- N, corresponding to CM_RCS_THRUST in nasspdefs.h
local entryInterface = 121920 -- m, 400,000 ft
local trimHandoffPressure = 1800 -- Pa
local cm=assert(vessel.get_interface("Charlie-Brown"))
local handle=assert(vessel.get_handle("Charlie-Brown"))
local earth=assert(oapi.get_gbody("Earth"))
local flight=assert(io.open("capsule-entry.csv","w"))
flight:write("time,event,altitude_m,earth_speed_m_s,vertical_m_s,g_load,heat_shield_error_deg,cm_mass_kg,ground_contact,airspeed_m_s,groundspeed_m_s,drogue,mains_attached,lat_deg,lng_deg\n")
local function set(name,state,hold)
    cm:set_panelswitch(name,state,hold)
end
local function unitClamp(value)
    return math.max(-1,math.min(1,value))
end
local function localVector(v)
    return _V(vec.dotp(cm:globalrot(_V(1,0,0)),v),
        vec.dotp(cm:globalrot(_V(0,1,0)),v),vec.dotp(cm:globalrot(_V(0,0,1)),v))
end
local function availableJets()
    local result={}
    for i=0,cm:get_thrustercount()-1 do
        local thruster=cm:get_thrusterhandle(i)
        local maximum=cm:get_thrustermax0(thruster)
        if math.abs(maximum-cmJetThrust)<1 then
            local tank=cm:get_thrusterresource(thruster)
            if tank and cm:get_propellantmass(tank)>.1 then
                local force=vec.mul(cm:get_thrusterdir(thruster),maximum)
                local torque=vec.crossp(force,cm:get_thrusterpos(thruster))
                result[#result+1]={thruster=thruster,force=force,torque=torque,level=0}
            end
        end
    end
    return result
end
local function commandJetTorque(acceleration)
    local pmi=cm:get_pmi()
    local mass=cm:get_mass()
    local torque=_V(acceleration.x*pmi.x*mass,acceleration.y*pmi.y*mass,acceleration.z*pmi.z*mass)
    local force=_V(0,0,0)
    local jets=availableJets()
    assert(#jets>0,"No pressurized command-module jets")
    -- Fit jet levels to the requested torque while penalizing net translation.
    for _=1,6 do
        for _,jet in ipairs(jets) do
            local fit=(vec.dotp(jet.torque,torque)-.34*vec.dotp(jet.force,force))/
                (vec.dotp(jet.torque,jet.torque)+.34*vec.dotp(jet.force,jet.force))
            local level=math.min(1,math.max(0,jet.level+fit))
            local change=level-jet.level
            jet.level=level
            torque=vec.sub(torque,vec.mul(jet.torque,change))
            force=vec.add(force,vec.mul(jet.force,change))
        end
    end
    for _,jet in ipairs(jets) do
        if jet.level>.0001 then cm:set_thrusterlevel_singlestep(jet.thruster,jet.level) end
    end
end

local function align(retro, attitudeUp)
    local z = localVector(retro)
    local y = localVector(attitudeUp)
    local error = math.acos(unitClamp(z.z))
    local axis = vec.crossp(_V(0,0,1),z)
    local omega=_V(0,0,0)
    if vec.length(axis)>1e-6 then omega=vec.mul(vec.unit(axis),-math.min(math.rad(2.7),error*.13)) end
    if error<math.rad(35) then
        local roll=math.atan2(y.x,y.y)
        omega.z=math.max(-math.rad(1.2),math.min(math.rad(1.2),roll*.14))
    end
    commandJetTorque(vec.mul(vec.sub(omega,cm:get_angvel()),1.9))
    return error
end

local stepTime = oapi.get_simtime()
local lastV = oapi.get_relativevel(handle,earth)
local function telemetry(event,alpha)
    local r=oapi.get_relativepos(handle,earth)
    local v=oapi.get_relativevel(handle,earth)
    local now=oapi.get_simtime()
    local radius=vec.length(r)
    local acceleration=vec.mul(r,-3.986004418e14/radius^3)
    local dt=now-stepTime
    local g=0
    if dt>0 then
        g=vec.length(vec.sub(vec.mul(vec.sub(v,lastV),1/dt),acceleration))/9.80665
    end
    stepTime,lastV=now,v
    local height=cm:get_altitude()
    local drogue=vessel.get_handle("AS-505-DROGUECHUTE")
    local mains=vessel.get_handle("AS-505-MAINCHUTE")
    local port=cm:get_attachmenthandle(false,1)
    local location=cm:get_equpos()
    flight:write(string.format("%.3f,%s,%.3f,%.5f,%.5f,%.5f,%.5f,%.4f,%s,%.6f,%.6f,%s,%s,%.7f,%.7f\n",
        now,event,height,vec.length(v),vec.dotp(r,v)/radius,g,math.deg(alpha or 0),cm:get_mass(),tostring(cm:get_groundcontact()),
        cm:get_airspeed(),cm:get_groundspeed(),tostring(drogue~=nil),tostring(mains and port and cm:get_attachmentstatus(port)==mains or false),
        math.deg(location.lat),math.deg(location.lng)))
    flight:flush()
    return height
end
proc.wait_simdt(1)
oapi.set_focusobject("Charlie-Brown")
telemetry("entry-preparation")
for _,name in ipairs({"GNComputerMnACircuitBraker","GNComputerMnBCircuitBraker","PyroArmASwitch","PyroArmBSwitch",
    "ELSLogicSwitch","ELSAutoSwitch","SECSArmBatACircuitBraker","SECSArmBatBCircuitBraker","SECSLogicBatACircuitBraker","SECSLogicBatBCircuitBraker","ELSBatACircuitBraker","ELSBatBCircuitBraker","CMRCSLogicSwitch","RCSLogicMnACircuitBraker","RCSLogicMnBCircuitBraker"}) do
    set(name,1)
end
set("MainBusTieBatAcSwitch",2)
set("MainBusTieBatBcSwitch",2)
set("SECSLogic1Switch",1,true)
set("SECSLogic2Switch",1,true)
proc.wait_simdt(2)
set("CsmLmFinalSep1Switch",1,true)
set("CsmLmFinalSep2Switch",1,true)
proc.wait_simdt(3)
set("CsmLmFinalSep1Switch",0)
set("CsmLmFinalSep2Switch",0)
assert(vessel.get_handle("AS-505-DCKPRB"),"Docking-probe assembly still blocks the apex cover")
telemetry("docking-probe-jettison")
set("CMRCSPressSwitch",1,true)
set("CMRCSProp1Switch",2,true)
set("CMRCSProp2Switch",2,true)
proc.wait_simdt(2)
set("CMRCSPressSwitch",0)
set("CMRCSProp1Switch",1)
set("CMRCSProp2Switch",1)
set("CmSmSep1Switch",1,true)
set("CmSmSep2Switch",1,true)
proc.wait_simdt(9)
set("CmSmSep1Switch",0)
set("CmSmSep2Switch",0)
telemetry("service-module-separated")
assert(cm:get_mass()<7500,"The service module did not separate")
cm:set_rcsmode(1)
set("SCContSwitch",0)
set("CMCModeSwitch",0)
set("AttRateSwitch",0)
set("AttDeadbandSwitch",0)
set("THCRotary",1)
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do
    set("BMAG"..axis.."Switch",2)
    set("ManualAtt"..axis.."Switch",2)
end
local nextTelemetry=0
local inAtmosphere=false
local crossed=false
-- 0 degrees puts the lift down. This bank retains a component of upward
-- lift to limit deceleration while allowing capture on this trajectory.
local entryBank=math.rad(125)
while true do
    local now=oapi.get_simtime()
    local height=cm:get_altitude()
    local r=oapi.get_relativepos(handle,earth)
    local v=oapi.get_relativevel(handle,earth)
    local speedVector=cm:get_airspeedvector(REFFRAME.GLOBAL)
    if vec.length(speedVector)<1 then speedVector=v end
    local retro=vec.mul(vec.unit(speedVector),-1)
    local radialUp=vec.unit(vec.sub(r,vec.mul(retro,vec.dotp(r,retro))))
    local up=vec.add(vec.mul(radialUp,math.cos(entryBank)),
        vec.mul(vec.crossp(retro,radialUp),math.sin(entryBank)))
    local q=cm:get_dynpressure()
    local angle
    if not inAtmosphere and q<trimHandoffPressure and cm:get_airspeed()>900 then
        angle=align(retro,up)
    else
        if not inAtmosphere then
            inAtmosphere=true
            cm:set_rcsmode(0)
            telemetry("aerodynamic-trim",math.acos(unitClamp(vec.dotp(cm:globalrot(_V(0,0,1)),retro))))
        end
        angle=math.acos(unitClamp(vec.dotp(cm:globalrot(_V(0,0,1)),retro)))
    end
    if not crossed and height<entryInterface then
        crossed=true
        telemetry("entry-interface",angle)
        local fpa=math.deg(math.asin(vec.dotp(vec.unit(r),vec.unit(v))))
        print("Apollo 10 entry interface",height,vec.length(v),fpa)
    end
    assert(not (crossed and height>entryInterface and vec.dotp(r,v)>0), "Capsule skipped out of the atmosphere")
    if now>=nextTelemetry then
        telemetry(inAtmosphere and "entry" or "heat-shield-align",angle)
        nextTelemetry=now+(height>150000 and 10 or 1)
    end
    if cm:get_groundcontact() then
        telemetry("ground-contact")
        assert(vessel.get_handle("AS-505-DROGUECHUTE"),"Drogue missing at contact")
        local main=vessel.get_handle("AS-505-MAINCHUTE")
        local port=cm:get_attachmenthandle(false,1)
        assert(main and port and cm:get_attachmentstatus(port)==main,"Mains not attached at contact")
        assert(crossed,"Missing entry-interface crossing")
        assert(cm:get_airspeed()<16,"Excessive airspeed at contact")
        break
    end
    proc.wait_frames(1)
end
flight:close()
