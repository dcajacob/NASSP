-- Reload the actual SPS-3 output, shut down the burn systems and coast in P00.
local ship=assert(vessel.get_interface("AS-205"))
local earth=assert(oapi.get_gbody("Earth"))
local report=assert(io.open("postburn.csv","w"))
report:write("elapsed_s,event,program,verb,noun,sps_mass,periapsis_m,apoapsis_m,agc_get_s\n")
local sps
for i=0,ship:get_propellantcount()-1 do
    local tank=ship:get_propellanthandle(i)
    if not sps or ship:get_propellantmaxmass(tank)>ship:get_propellantmaxmass(sps) then sps=tank end
end
local initialMass=ship:get_propellantmass(sps)
local function record(event)
    local _,orbit=ship:get_elementsex(earth)
    local radius=oapi.get_size(earth)
    local clock=((ship:get_agcerasable(0,20)%16384)*16384+ship:get_agcerasable(0,21)%16384)/100
    report:write(string.format("%.6f,%s,%d,%d,%d,%.6f,%.6f,%.6f,%.2f\n",
        oapi.get_simtime(),event,ship:get_agcerasable(2,9),ship:get_agcerasable(2,1),
        ship:get_agcerasable(2,2),ship:get_propellantmass(sps),orbit.PeD-radius,orbit.ApD-radius,clock))
    report:flush()
    assert(math.abs(ship:get_propellantmass(sps)-initialMass)<.005,"SPS restarted after reload")
end
local function set(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value,name)
end
local names={V="Verb",E="Enter",R="Reset",K="KeyRel",["0"]="Zero",["3"]="Three",["7"]="Seven"}
local function keys(sequence)
    for char in sequence:gmatch(".") do
        local key="DskySwitch"..assert(names[char])
        ship:set_panelswitch(key,1,true)
        proc.wait_simdt(.375)
        ship:set_panelswitch(key,0)
        proc.wait_simdt(.375)
    end
end
local function waitPrompt(v,n,limit)
    local untilTime=oapi.get_simtime()+limit
    repeat
        if ship:get_agcerasable(2,1)==v and ship:get_agcerasable(2,2)==n then return end
        record("awaiting_program_selection")
        proc.wait_simdt(.5)
    until oapi.get_simtime()>=untilTime
    error("Missing post-burn DSKY prompt "..v.."/"..n)
end
proc.wait_simdt(1)
record("reloaded_sps3")
set("SCContSwitch",0)
set("CMCModeSwitch",0)
for _,name in ipairs({"SCSTvcPitchSwitch","SCSTvcYawSwitch","EMSModeSwitch"}) do set(name,1) end
set("EMSFunctionSwitch",0)
for _,name in ipairs({"Pitch1Switch","Pitch2Switch","Yaw1Switch","Yaw2Switch",
    "MainBusTieBatAcSwitch","MainBusTieBatBcSwitch","TransContrSwitch",
    "PitchBatACircuitBraker","PitchBatBCircuitBraker","YawBatACircuitBraker","YawBatBCircuitBraker"}) do
    set(name,0)
end
set("TVCServoPower1Switch",1)
set("TVCServoPower2Switch",1)
keys("KRV37E")
waitPrompt(37,0,30)
keys("00E")
local deadline=oapi.get_simtime()+30
while ship:get_agcerasable(2,9)~=0 do
    assert(oapi.get_simtime()<deadline,"CMC did not return to P00")
    record("awaiting_p00")
    proc.wait_simdt(.5)
end
record("p00_shutdown_complete")
oapi.set_tacc(10)
local endTime=oapi.get_simtime()+1800
while oapi.get_simtime()<endTime do
    proc.wait_simdt(math.min(60,endTime-oapi.get_simtime()))
    record("post_sps3_coast")
end
oapi.set_tacc(1)
proc.wait_simdt(2)
record("post_sps3_continuation_complete")
assert(ship:get_agcerasable(2,9)==0,"CMC left P00 during coast")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
