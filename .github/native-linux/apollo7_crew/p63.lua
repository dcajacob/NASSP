-- initialMET and separationMET come from the actual retrofire target and output save.

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
    -- Use powered direct RHC hard-stop pulses. Both transfer relays are
    -- checked at separation. Normal-mode RHC can be unavailable on this bus configuration.
    set("RotPowerDirect1Switch",2)
    set("RotPowerDirect2Switch",2)
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
            oapi.simulateimmediatekey(error>0 and axis[3] or axis[4],OAPI_KEY.LALT)
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
        oapi.simulateimmediatekey(rate>0 and axis[4] or axis[3],OAPI_KEY.LALT)
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
assert(ship:get_agcerasable(2,9)==62 and present("SM")==1,"Expected separated CM in P62")
sample("cm_separation_reloaded")
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
