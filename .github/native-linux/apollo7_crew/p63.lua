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
-- PRO releases the entry DAP to acquire the calculated trim attitude.
set("SCContSwitch",1)
set("CMCModeSwitch",2)
press("Prog")
proc.wait_simdt(5)
sample("entry_attitude_commanded")
set("EMSFunctionSwitch",4)
set("EMSModeSwitch",2)
set("AttRateSwitch",1)
set("AttDeadbandSwitch",1)

local deadline=oapi.get_simtime()+180
while ship:get_agcerasable(2,9)~=63 do
    assert(oapi.get_simtime()<deadline,"CMC did not enter P63")
    sample("waiting_for_p63")
    proc.wait_simdt(1)
end
sample("p63_entry_started")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
