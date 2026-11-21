-- Coast with a powered CMC and IMU. MCC uplinks are accepted on the crew menu.
local ship = assert(vessel.get_interface("AS-205"))
local report = assert(io.open("coast.csv", "w"))
report:write("get,event,state,substate,program,reference,periapsis_m,apoapsis_m\n")
local function get() return initial_get + oapi.get_simtime() end
local function switch(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value, name)
end
local function snapshot()
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local f = assert(io.open("saved.scn","rb"))
    local raw = f:read("*a")
    f:close()
    return raw
end
local function field(raw,key)
    local value=raw:match("\n  "..key.." ([^\r\n]+)")
    return value
end
local function record(event,raw)
    local _,orbit=ship:get_elementsex(ship:get_gravityref())
    local r=oapi.get_size(ship:get_gravityref())
    report:write(string.format("%.3f,%s,%d,%d,%d,%d,%.3f,%.3f\n",get(),event,
        tonumber(field(raw,"MCC_MissionState")),tonumber(field(raw,"MCC_SubState")),
        ship:get_agcerasable(2,9),math.floor(ship:get_agcerasable(0,63)/4096)%2,orbit.PeD-r,orbit.ApD-r))
    report:flush()
    assert(ship:get_altitude(1)>100000,"CSM reentered during orbital coast")
end
local function key(name)
    ship:set_panelswitch("DskySwitch"..name,1,true)
    proc.wait_simdt(.375)
    ship:set_panelswitch("DskySwitch"..name,0)
    proc.wait_simdt(.375)
end
local function p00()
    if ship:get_agcerasable(2,9)==0 then return end
    key("KeyRel")
    key("Reset")
    key("Verb"); key("Three"); key("Seven"); key("Enter")
    proc.wait_simdt(1)
    key("Zero"); key("Zero"); key("Enter")
    local limit=get()+50
    while ship:get_agcerasable(2,9)~=0 do
        assert(get()<limit,"Unable to select P00 after burn")
        proc.wait_simdt(.5)
    end
end
local function coast_until(target)
    while get()<target do
        oapi.set_tacc(80)
        proc.wait_simdt(math.min(240,target-get()))
    end
    oapi.set_tacc(1)
    proc.wait_simdt(1)
end
local function accept(raw)
    switch("PCMBitRateSwitch",1)
    switch("UPTLMSwitch1",1)
    ship:set_panelswitch("UPTLMSwitch2",2,true)
    proc.wait_simdt(.75)
    ship:set_panelswitch("UPTLMSwitch2",1)
    switch("CMUplinkSwitch",1)
    proc.wait_simdt(1)
    oapi.simulatebufferedkey(OAPI_KEY.TAB)
    proc.wait_simdt(2)
    oapi.simulatebufferedkey(0x03)
    local limit=get()+900
    local active=false
    repeat
        proc.wait_simdt(2)
        local p=ship:get_agcerasable(2,9)
        active = active or p==27 or ship:get_agcuplinkstatus()~=0
        if active and p==0 and ship:get_agcuplinkstatus()==0 then
            proc.wait_simdt(8)
            if ship:get_agcerasable(2,9)==0 and ship:get_agcuplinkstatus()==0 then break end
        end
    until get()>=limit
    assert(active and get()<limit,"Coast navigation uplink did not finish")
    switch("CMUplinkSwitch",0)
    switch("PCMBitRateSwitch",0)
    record("navigation_uplink",snapshot())
end
proc.wait_simdt(2)
p00()
-- FREE drift with power retained to the guidance platform. Isolate both start
-- batteries and turn the SPS gimbal motors off for the multi-orbit coast.
switch("SCContSwitch",1)
switch("CMCModeSwitch",0)
switch("LimitCycleSwitch",0)
for _,name in ipairs({"MainBusTieBatAcSwitch","MainBusTieBatBcSwitch","Pitch1Switch","Yaw1Switch","Pitch2Switch","Yaw2Switch"}) do switch(name,0) end
record("coast_start",snapshot())
for _,event in ipairs(schedule) do
    coast_until(event[1])
    local raw=snapshot()
    record("coast_update",raw)
    if event[2] then
        local expected=event[2]
        local limit=get()+240
        while tonumber(field(raw,"MCC_MissionState"))~=expected or field(raw,"MCC_PCOption_Text")~="Ready for uplink" do
            assert(get()<limit,"Missing MCC update "..expected)
            proc.wait_simdt(4)
            raw=snapshot()
        end
        if expected==burn_state then
            assert(field(raw,"MCC_AP7MNV_purpose")==burn_purpose,"Wrong maneuver PAD")
            record("maneuver_pad_ready",raw)
        else
            accept(raw)
        end
    elseif event[3]=="oxygen" or event[3]=="hydrogen" then
        for i=1,3 do
            local sw="FuelCellPurge"..i.."Switch"
            switch(sw,event[3]=="oxygen" and 0 or 2)
            coast_until(get()+(event[3]=="oxygen" and 120 or 80))
            switch(sw,1)
        end
    elseif event[3]=="heater_on" then
        switch("H2PurgeLineSwitch",1)
    elseif event[3]=="heater_off" then
        switch("H2PurgeLineSwitch",0)
    end
end
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
