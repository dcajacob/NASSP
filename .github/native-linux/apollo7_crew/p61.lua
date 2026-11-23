local ship=vessel.get_focusinterface()
local output=assert(io.open("entry-cmc.csv","w"))
output:write("elapsed,phase,program,verb,noun,channel_163,roll_deg_s,pitch_deg_s,yaw_deg_s\n")
local digits={"Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine"}
local keyNames={V="Verb",E="Enter",P="Prog",N="Noun",R="Reset",K="KeyRel",["+"]="Plus",["-"]="Minus"}

local function sample(phase)
    local program,verb,noun=ship:get_agcerasable(2,9),ship:get_agcerasable(2,1),ship:get_agcerasable(2,2)
    local rate=ship:get_angvel()
    output:write(string.format("%.3f,%s,%d,%d,%d,%d,%.6f,%.6f,%.6f\n",
        oapi.get_simtime(),phase,program,verb,noun,ship:get_agcchannel(0x73),math.deg(rate.z),math.deg(rate.x),math.deg(rate.y)))
    output:flush()
    return program,verb,noun
end
local function set(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value,"Switch did not move: "..name)
end
local function keys(sequence)
    for char in sequence:gmatch(".") do
        local name="DskySwitch"..(keyNames[char] or digits[tonumber(char)+1])
        ship:set_panelswitch(name,1,true)
        proc.wait_simdt(.375)
        ship:set_panelswitch(name,0)
        proc.wait_simdt(.25)
    end
end
local function waitPrompt(v,n,phase,seconds)
    local deadline=oapi.get_simtime()+seconds
    repeat
        local program,verb,noun=sample(phase)
        if verb==v and noun==n then return end
        proc.wait_simdt(.5)
    until oapi.get_simtime()>=deadline
    error("Missing DSKY prompt "..v.."/"..n)
end



set("SCContSwitch",1)
set("CMCModeSwitch",0)
proc.wait_simdt(2)
local program,verb,noun=sample("postburn_cmc")
assert(program==40,"Expected the flown P40 postburn state")
if (verb==6 or verb==16) and noun==40 then
    keys("P")
    waitPrompt(16,85,"p40_residual",30)
    proc.wait_simdt(1)
end
keys("P")
waitPrompt(37,0,"p40_complete_program_request",30)
proc.wait_simdt(2)
keys("00E")
local deadline=oapi.get_simtime()+35
while sample("postburn_program_exit")~=0 do
    assert(oapi.get_simtime()<deadline,"CMC did not return to P00 after P40")
    proc.wait_simdt(2)
end
-- The calibrated retrofire platform remains usable throughout entry. P61
-- can start directly in this reference without a moving-vehicle coarse align.
assert(math.floor(ship:get_agcerasable(0,63)/4096)%2==1,"CMC has no valid retrofire reference")
keys("V37E")
waitPrompt(37,0,"entry_program_requested",20)
keys("61E")
waitPrompt(6,61,"p61_entry_target",35)
sample("p61_target_display")
keys("P")
waitPrompt(6,60,"p61_g_load_and_gamma",40)
sample("p61_predicted_entry")
keys("P")
waitPrompt(6,63,"p61_range_and_entry_time",40)
sample("p61_range_and_time")
keys("P")
waitPrompt(50,25,"p62_service_module_separation_request",40)
assert(ship:get_agcerasable(2,9)==62,"P62 never started")
sample("p62_waiting_for_service_module_sep")
output:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
