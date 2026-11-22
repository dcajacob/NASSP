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
while sample("before_p52")~=0 do
    assert(oapi.get_simtime()<deadline,"CMC did not return to P00 before P52")
    proc.wait_simdt(2)
end
-- Damp residual pitch and yaw from SPS shutdown before torquing the stable member.
set("SCContSwitch",0)
set("AttRateSwitch",0)
set("AttDeadbandSwitch",0)
set("LimitCycleSwitch",0)
for _,axis in ipairs({"Roll","Pitch","Yaw"}) do
    set("BMAG"..axis.."Switch",2)
    set("ManualAtt"..axis.."Switch",1)
end

local axes={{"Pitch","x",OAPI_KEY.NUMPAD2,OAPI_KEY.NUMPAD8},
            {"Yaw","y",OAPI_KEY.NUMPAD1,OAPI_KEY.NUMPAD3},
            {"Roll","z",OAPI_KEY.NUMPAD6,OAPI_KEY.NUMPAD4}}
set("RotPowerDirect1Switch",2)
set("RotPowerDirect2Switch",2)
ship:set_rcsmode(1)
for _,a in ipairs(axes) do set("ManualAtt"..a[1].."Switch",2) end
local trimDeadline=oapi.get_simtime()+130
repeat
    local rates=ship:get_angvel()
    local best=axes[1]
    for _,a in ipairs(axes) do if math.abs(rates[a[2]])>math.abs(rates[best[2]]) then best=a end end
    if vec.length(rates)<math.rad(.028) then
        proc.wait_simdt(.75)
        if vec.length(ship:get_angvel())<math.rad(.032) then break end
    end
    oapi.simulateimmediatekey(rates[best[2]]>0 and best[4] or best[3],OAPI_KEY.LALT)
    proc.wait_frames(1)
    proc.wait_simdt(.30)
until oapi.get_simtime()>=trimDeadline
assert(vec.length(ship:get_angvel())<math.rad(.04),"Residual rates too high for entry platform alignment")
ship:set_rcsmode(0)
set("SCContSwitch",1)
set("CMCModeSwitch",0)
for _,a in ipairs(axes) do set("ManualAtt"..a[1].."Switch",1) end
sample("postburn_rates_trimmed")

keys("V37E52E")
waitPrompt(4,6,"p52_alignment_option",24)
keys("V22E")
waitPrompt(22,6,"p52_set_nominal_alignment",12)
keys("00002EP")
waitPrompt(6,34,"p52_alignment_time",30)
keys("P")
waitPrompt(6,22,"p52_planned_gimbal_angles",65)
sample("p52_requested_entry_frame")
keys("P")
waitPrompt(50,25,"p52_coarse_align_complete",70)
proc.wait_simdt(3)
sample("p52_entry_reference_aligned")
assert(math.floor(ship:get_agcerasable(0,63)/4096)%2==1,"CMC lost the REFSMMAT valid flag")
keys("V34E")
proc.wait_simdt(2)
keys("V37E")
waitPrompt(37,0,"exit_p52_program_request",20)
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
