-- Coast to the next Mission Control advisory and save the live PAD.
local ship = assert(vessel.get_interface("AS-205"))
local target = assert(vessel.get_handle("AS-205-S4BSTG"))
local report = assert(io.open("coast.csv","w"))
report:write("get,event,state,substate,periapsis_m,apoapsis_m,range_m\n")
local function get() return start_get + oapi.get_simtime() end
local function snapshot()
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local stream = assert(io.open("saved.scn","rb"))
    local raw = stream:read("*a")
    stream:close()
    return raw
end
local function field(raw,key)
    return raw:match("\n  "..key.." ([^\r\n]+)")
end
ship:set_panelswitch("SCContSwitch",1)
ship:set_panelswitch("CMCModeSwitch",0)
while get() < advisory_get do
    oapi.set_tacc(80)
    proc.wait_simdt(math.min(120,advisory_get-get()))
    assert(ship:get_altitude(1)>100000,"CSM reentered during rendezvous coast")
end
oapi.set_tacc(1)
local raw = snapshot()
while tonumber(field(raw,"MCC_MissionState"))~=advisory_state
        or (require_uplink and field(raw,"MCC_PCOption_Text")~="Ready for uplink") do
    assert(get()<advisory_get+300,"Missing MCC advisory "..advisory_state)
    proc.wait_simdt(3)
    raw=snapshot()
end
local earth=ship:get_gravityref()
local _,orbit=ship:get_elementsex(earth)
local radius=oapi.get_size(earth)
report:write(string.format("%.3f,advisory,%s,%s,%.3f,%.3f,%.3f\n",get(),
    field(raw,"MCC_MissionState"),field(raw,"MCC_SubState"),orbit.PeD-radius,orbit.ApD-radius,
    vec.length(vec.sub(oapi.get_globalpos(target),ship:get_globalpos()))))
report:close()
