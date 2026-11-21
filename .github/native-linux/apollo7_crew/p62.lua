-- initialMET and separationMET come from the actual retrofire target and output save.

local ship = vessel.get_focusinterface()
local earth = ship:get_gravityref()
local report = assert(io.open("deorbit-to-entry.csv", "w"))
report:write("met,marker,altitude,airspeed,heatshield_angle,body_rate,tacc,sm,apex,drogue,main,floatbag,program,verb,noun\n")
local function present(name)
    return oapi.get_objhandle("AS-205-"..name) and 1 or 0
end
local function sample(marker)
    local rot = ship:get_rotationmatrix()
    local v = vec.unit(ship:get_relativevel(earth))
    local dot = -v.x*rot.m13-v.y*rot.m23-v.z*rot.m33
    local angle = math.deg(math.acos(math.max(-1,math.min(1,dot))))
    report:write(string.format("%.2f,%s,%.4f,%.4f,%.3f,%.5f,%.1f,%d,%d,%d,%d,%d,%d,%d,%d\n",
        initialMET+oapi.get_simtime(), marker, ship:get_altitude(1), ship:get_airspeed(),
        angle, vec.length(ship:get_angvel()), oapi.get_tacc(), 
        present("SM"),present("APEX"),present("DROGUECHUTE"),present("MAINCHUTE"),present("FLOATBAG"),ship:get_agcerasable(2,9),
        ship:get_agcerasable(2,1),ship:get_agcerasable(2,2)))
    report:flush()
end
local function set(name, value, hold)
    ship:set_panelswitch(name, value, hold)
    assert(ship:get_panelswitch(name)==value,"Switch did not move: "..name)
end
local function press(key)
    local name = "DskySwitch" .. key
    set(name, 1, true)
    proc.wait_simdt(0.5)
    set(name, 0)
    proc.wait_simdt(0.5)
end
local function waitUntilPrompt(verb,noun,timeout)
    local limit=oapi.get_simtime()+timeout
    while ship:get_agcerasable(2,1)~=verb or ship:get_agcerasable(2,2)~=noun do
        if oapi.get_simtime()>=limit then return false end
        proc.wait_simdt(.25)
    end
    return true
end

local function checkpoint(name)
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local file=assert(io.open("saved.scn","rb"))
    local state=file:read("*a")
    file:close()
    local output=assert(io.open(name..".scn","wb"))
    output:write(state)
    output:close()
end

local function alignHeatshield()
    set("SCContSwitch",0)
    set("AttRateSwitch",0)
    for _,axis in ipairs({"Roll","Pitch","Yaw"}) do set("ManualAtt"..axis.."Switch",2) end
    ship:set_rcsmode(1)
    local axes={
        {"Pitch","x",OAPI_KEY.NUMPAD2,OAPI_KEY.NUMPAD8},
        {"Yaw","y",OAPI_KEY.NUMPAD1,OAPI_KEY.NUMPAD3},
        {"Roll","z",OAPI_KEY.NUMPAD6,OAPI_KEY.NUMPAD4},
    }
    local function largest(v)
        local axis=axes[1]
        for _,candidate in ipairs(axes) do
            if math.abs(v[candidate[2]])>math.abs(v[axis[2]]) then axis=candidate end
        end
        return axis,v[axis[2]]
    end
    local deadline=oapi.get_simtime()+150
    local nextLog=oapi.get_simtime()
    while oapi.get_simtime()<deadline do
        local direction=vec.mul(vec.unit(ship:get_relativevel(earth)),-1)
        local bodyTarget=_V(vec.dotp(direction,ship:globalrot(_V(1,0,0))),
                            vec.dotp(direction,ship:globalrot(_V(0,1,0))),
                            vec.dotp(direction,ship:globalrot(_V(0,0,1))))
        local rate=ship:get_angvel()
        local angle=math.acos(math.max(-1,math.min(1,bodyTarget.z)))
        local targetRate=_V(0,0,0)
        if angle>math.rad(12) then
            local axis=vec.crossp(_V(0,0,1),bodyTarget)
            targetRate=vec.mul(vec.unit(axis),-math.min(math.rad(1.4),angle*.20))
        elseif vec.length(rate)<math.rad(.35) then
            sample("entry_heatshield_coarsely_aligned")
            break
        end
        local axis,error=largest(vec.sub(targetRate,rate))
        if math.abs(error)>math.rad(.08) then
            oapi.simulateimmediatekey(error>0 and axis[3] or axis[4])
        end
        if oapi.get_simtime()>=nextLog then
            sample("entry_manual_coarse_attitude")
            nextLog=oapi.get_simtime()+4
        end
        proc.wait_frames(1)
    end
    assert(oapi.get_simtime()<deadline,"CM hand-controller slew did not reach entry attitude")
    for _,axis in ipairs(axes) do set("ManualAtt"..axis[1].."Switch",0) end
    for _=1,30 do
        local axis,rate=largest(ship:get_angvel())
        if math.abs(rate)<math.rad(.08) then break end
        oapi.simulateimmediatekey(rate>0 and axis[4] or axis[3])
        proc.wait_frames(1)
        proc.wait_frames(7)
    end
    ship:set_rcsmode(0)
    for _,axis in ipairs(axes) do set("ManualAtt"..axis[1].."Switch",1) end
    set("SCContSwitch",1)
    set("CMCModeSwitch",2)
    sample("entry_manual_trim_complete")
end

proc.wait_simdt(1)
assert(ship:get_agcerasable(2,9)==62)
sample("p62_request_received")
for _,name in ipairs({"SECSLogic1Switch","SECSLogic2Switch","PyroArmASwitch","PyroArmBSwitch"}) do
    set(name,1)
end
oapi.set_tacc(4)
while initialMET+oapi.get_simtime()<separationMET-12 and ship:get_altitude(1)>190000 do
    proc.wait_simdt(8)
end
oapi.set_tacc(1)
while initialMET+oapi.get_simtime()<separationMET and ship:get_altitude(1)>190000 do
    proc.wait_simdt(.25)
end
sample("before_sm_sep")
-- Complete both CM RCS transfer circuits before pressing the separation switches.
for _,name in ipairs({"BatCPWRCircuitBraker","BatCtoBatBusACircuitBraker","BatCtoBatBusBCircuitBraker",
                     "RCSLogicMnACircuitBraker","RCSLogicMnBCircuitBraker"}) do set(name,1) end
set("MainBusTieBatAcSwitch",2)
set("MainBusTieBatBcSwitch",2)
set("CmSmSep1Switch",1,true)
set("CmSmSep2Switch",1,true)
proc.wait_simdt(2)
set("CmSmSep1Switch",0)
set("CmSmSep2Switch",0)
set("CautionWarningCMCSMSwitch",0)
set("RCSTrnfrSwitch",2,true)
proc.wait_simdt(3)
set("RCSTrnfrSwitch",1)
set("CMRCSLogicSwitch",0)
assert(present("SM")==1,"Service module did not separate")
sample("after_sm_sep")
checkpoint("rcs-transfer")
local transferFile=assert(io.open("rcs-transfer.scn","rb"))
local transfer=transferFile:read("*a")
transferFile:close()
assert(transfer:match("CMTRANSFERMOTOR1 1") and transfer:match("CMTRANSFERMOTOR2 1"),
       "Both CM RCS transfer relays must energize")
sample("cm_rcs_transfer_confirmed")

set("SCContSwitch",1)
set("CMCModeSwitch",2)
for _,axis in ipairs({"Roll","Pitch","Yaw"}) do set("BMAG"..axis.."Switch",2) end
for _,name in ipairs({"BdRollB1Switch","BdRollB2Switch","PitchC3Switch","PitchA4Switch",
                     "YawB3Switch","YawD4Switch"}) do set(name,2) end
for _,name in ipairs({"AcRollA1Switch","AcRollA2Switch","AcRollC1Switch","AcRollC2Switch",
                     "BdRollD1Switch","BdRollD2Switch","PitchA3Switch","PitchC4Switch",
                     "YawD3Switch","YawB4Switch"}) do set(name,1) end
for _,name in ipairs({"BDRollMnACircuitBraker","PitchMnACircuitBraker","YawMnACircuitBraker"}) do set(name,1) end
press("Enter")
proc.wait_simdt(4)
sample("p62_separation_acknowledged")
press("Prog")
if not waitUntilPrompt(6,61,80) then
    checkpoint("p62-entry-target-timeout")
    sample("p62_entry_target_timeout")
    error("P62 did not display its entry target")
end
sample("p62_entry_target_display")
alignHeatshield()
assert(waitUntilPrompt(6,61,10),"P62 target display was lost during the attitude slew")
press("Prog")
proc.wait_simdt(5)
sample("entry_attitude_commanded")
set("EMSFunctionSwitch",4)
set("EMSModeSwitch",2)
set("AttRateSwitch",1)
set("AttDeadbandSwitch",1)

local deadline=oapi.get_simtime()+25
while ship:get_agcerasable(2,9)~=63 do
    assert(oapi.get_simtime()<deadline,"CMC did not enter P63")
    proc.wait_simdt(.25)
end
sample("p63_entry_started")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
