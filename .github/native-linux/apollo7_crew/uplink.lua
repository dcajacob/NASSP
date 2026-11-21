-- "loads" describes the packets actually prepared by Mission Control in the preceding save.
local ship=vessel.get_focusinterface()
local report=assert(io.open("uplink.csv","w"))
report:write("phase,simtime,program,pending\n")
local function event(phase)
    report:write(string.format("%s,%.3f,%d,%d\n",phase,oapi.get_simtime(),
        ship:get_agcerasable(2,9),ship:get_agcuplinkstatus()))
    report:flush()
end
local function installed(load)
    for i,word in ipairs(load.words) do
        if ship:get_agcerasable(load.bank,load.address+i-1)~=word then return false end
    end
    return true
end
proc.wait_simdt(2)
if #loads==4 then
    -- Let P00 finish its navigation work after restoring the deorbit coast.
    -- If Pinball is busy when the first V71 arrives, P27 can remain at V21 N01.
    proc.wait_simdt(20)
    local deadline=oapi.get_simtime()+120
    while math.floor(ship:get_agcchannel(9)/2)%2==1 do
        assert(oapi.get_simtime()<deadline,"CMC remained busy before retrofire uplink")
        proc.wait_simdt(.25)
    end
end
assert(ship:get_agcerasable(2,9)==0,"CAPCOM uplink requires CMC P00")
ship:set_panelswitch("PCMBitRateSwitch",1)
ship:set_panelswitch("UPTLMSwitch1",1)
ship:set_panelswitch("UPTLMSwitch2",2,true)
proc.wait_simdt(.75)
ship:set_panelswitch("UPTLMSwitch2",1)
ship:set_panelswitch("CMUplinkSwitch",1)
proc.wait_simdt(1)
oapi.simulatebufferedkey(OAPI_KEY.TAB)
proc.wait_simdt(2)
oapi.simulatebufferedkey(0x03)
event("accepted")
local quiet=0
local deadline=oapi.get_simtime()+1200
repeat
    proc.wait_simdt(.5)
    local all=true
    for _,load in ipairs(loads) do
        if not load.seen and installed(load) then
            event(load.name)
            load.seen=true
        end
        if not load.seen then all=false end
    end
    if all and ship:get_agcerasable(2,9)==0 and ship:get_agcuplinkstatus()==0 then
        quiet=quiet+1
    else
        quiet=0
    end
until quiet>=8 or oapi.get_simtime()>deadline
assert(quiet>=8,"CMC did not receive and finish processing all MCC packets")
ship:set_panelswitch("CMUplinkSwitch",0)
ship:set_panelswitch("PCMBitRateSwitch",0)
event("target_uplink_verified")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
