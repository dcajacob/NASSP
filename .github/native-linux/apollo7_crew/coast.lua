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
    -- V71 loads apply as separate P27 jobs. P00 and an empty uplink queue
    -- alone can occur between packets, so read each bank during transfer.
    local packet=assert(field(raw,"MCC_upString"))
    local loads={}
    local function add(bank,offset,payload,count)
        local words={}
        for digits in payload:gmatch("([0-7]+)E") do words[#words+1]=tonumber(digits,8) end
        assert(#words==count,"Truncated MCC navigation uplink")
        loads[#loads+1]={bank=bank,offset=offset,words=words}
    end
    if tonumber(field(raw,"MCC_MissionState"))==132 then
        add(4,4,assert(packet:match("^V71E5E2004E([0-7E]+)V33E$")),3)
    else
        for slot,payload in packet:gmatch("V71E21E1501E([0-7]+)E([0-7E]+)V33E") do
            assert(slot==(#loads==0 and "1" or "77776"),"Unexpected CSM vector slot")
            add(3,slot=="1" and 0x6c or 0x96,payload,14)
        end
        assert(#loads==2,"Missing second CSM vector")
    end
    local function verified()
        local complete=true
        for _,load in ipairs(loads) do
            if not load.received then
                local correct=true
                for i,word in ipairs(load.words) do
                    if ship:get_agcerasable(load.bank,load.offset+i-1)~=word then correct=false; break end
                end
                load.received=correct
            end
            complete=complete and load.received
        end
        return complete
    end
    local state=tonumber(field(raw,"MCC_MissionState"))
    local function dpTime(bank,offset)
        return ((ship:get_agcerasable(bank,offset)%16384)*16384+ship:get_agcerasable(bank,offset+1)%16384)/100
    end
    local age=dpTime(0,20)-dpTime(3,0x78)
    local trace=assert(io.open("navigation-timing.csv","a"))
    if trace:seek("end")==0 then trace:write("mission_state,get_s,vector_age_s,channel_11\n") end
    trace:write(string.format("%d,%.3f,%.2f,%d\n",state,get(),age,ship:get_agcchannel(9)))
    trace:close()
    if state==72 or (burn_state>=134 and #loads==2 and age>=1200) then
        -- This long-coast update loads two future-tagged vectors. P00 may
        -- already have a rectification job outstanding when warp comes off.
        local function epoch()
            return ship:get_agcerasable(3,0x78)*16384+ship:get_agcerasable(3,0x79)
        end
        local previous=epoch()
        local deadline=get()+1800
        while epoch()==previous do
            assert(get()<deadline,"P00 did not finish its coast navigation cycle")
            proc.wait_simdt(.5)
        end
        proc.wait_simdt(25)
        while math.floor(ship:get_agcchannel(9)/2)%2==1 do
            assert(get()<deadline+120,"CMC remained busy before coast uplink")
            proc.wait_simdt(.25)
        end
    end
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
    repeat
        proc.wait_simdt(.5)
        if verified() and ship:get_agcerasable(2,9)==0 and ship:get_agcuplinkstatus()==0 then break end
    until get()>=limit
    if get()>=limit then
        record("navigation_timeout",snapshot())
        error(string.format("Coast navigation uplink missed readback (P%d V%d N%d, %d queued)",
            ship:get_agcerasable(2,9),ship:get_agcerasable(2,1),ship:get_agcerasable(2,2),ship:get_agcuplinkstatus()))
    end
    switch("CMUplinkSwitch",0)
    switch("PCMBitRateSwitch",0)
    record("navigation_uplink",snapshot())
end
proc.wait_simdt(2)
if burn_state==163 then
    -- Restore the controllers after SPS-7 manual TVC before the retrofire coast.
    switch("THCRotary",1)
    ship:set_rcsmode(0)
    for _,axis in ipairs({"Pitch","Yaw","Roll"}) do switch("ManualAtt"..axis.."Switch",1) end
end
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
    elseif event[3]=="charge_b" or event[3]=="check_charge_a" then
        local b=event[3]=="charge_b"
        local a=assert(tonumber(raw:match("<BATTERY>%s+BATTERY_A%s+([%d.]+)")))
        if b or a<2500000 then
            for _,name in ipairs({"MainBusTieBatAcSwitch","MainBusTieBatBcSwitch",
                "BatBusAToPyroBusTieCircuitBraker","BatBusBToPyroBusTieCircuitBraker",
                "BatCtoBatBusACircuitBraker","BatCtoBatBusBCircuitBraker"}) do switch(name,0) end
            switch(b and "BATRLYBusBatBCircuitBraker" or "BATRLYBusBatACircuitBraker",0)
            switch("DCIndicatorsRotary",7)
            switch("BatteryChargeRotary",b and 2 or 1)
        end
    elseif event[3]=="stop_charge" then
        switch("BatteryChargeRotary",0)
        switch("BATRLYBusBatACircuitBraker",1)
        switch("BATRLYBusBatBCircuitBraker",1)
        switch("DCIndicatorsRotary",3)
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
