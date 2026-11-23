local ship=vessel.get_focusinterface()
local output=assert(io.open("prepare-p40.csv","w"))
output:write("elapsed,phase,program,verb,noun,channel_163,roll_deg_s,pitch_deg_s,yaw_deg_s\n")
local digits={"Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine"}
local keyNames={V="Verb",E="Enter",P="Prog",N="Noun",["+"]="Plus",["-"]="Minus"}

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
    error("Missing P40 preparation prompt "..v.."/"..n)
end

local switches={"ASCPRollSwitch","ASCPPitchSwitch","ASCPYawSwitch"}
local function followIMU()
    for axis,name in ipairs(switches) do
        local degrees=ship:get_agcerasable(0,25+axis)*360/32768
        local tenths=math.floor(10*degrees+.5)%3600
        set(name,tenths)
    end
end
proc.wait_simdt(1)
assert(sample("ready_for_gdc_alignment")==0,"GDC alignment requires CMC P00")

keys("V48E")
waitPrompt(4,46,"dap_config_before_powered_flight",16)
keys("V24E"..dap_config.."E"..roll_word.."E")
proc.wait_simdt(2)
assert(ship:get_agcerasable(6,54)==tonumber(dap_config,8) and
       ship:get_agcerasable(6,55)==tonumber(roll_word,8),"Incorrect N46 DAP setup")
keys("P")
waitPrompt(6,47,"dap_mass_request",14)
keys(string.format("V21E%+06dE",csm_weight))
waitPrompt(6,47,"dap_mass_loaded",20)
proc.wait_simdt(1)
keys("P")
waitPrompt(6,48,"dap_trim_request",14)
keys(string.format("V24E%+06dE%+06dE",pitch_trim,yaw_trim))
waitPrompt(6,48,"dap_trim_loaded",22)
proc.wait_simdt(1)
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
local outputFile=assert(io.open("saved.scn","rb"))
local contents=outputFile:read("*a")
outputFile:close()
local readout=assert(contents:match("DSKY_BEGIN[^_].-DSKY_END"))
local function register(index)
    local digits=assert(readout:match(" R"..index.."%s+([+-]?[%d ]+)"))
    return assert(tonumber((digits:gsub(" ",""))))
end
assert(math.abs(register(1)-pitch_trim)<=3 and math.abs(register(2)-yaw_trim)<=3,
       "The CMC did not retain the SPS gimbal trim")
keys("P")
proc.wait_simdt(3)
keys("V46E")
local bdRoll=roll_word=="01111"
for _,axis in ipairs({"AC","BD"}) do
    for _,bus in ipairs({"MnA","MnB"}) do set(axis.."Roll"..bus.."CircuitBraker",1) end
end
for n=1,2 do
    set("AcRollA"..n.."Switch",bdRoll and 1 or 2)
    set("AcRollC"..n.."Switch",bdRoll and 1 or 0)
    set("BdRollB"..n.."Switch",bdRoll and 2 or 1)
    set("BdRollD"..n.."Switch",bdRoll and 0 or 1)
end
sample(bdRoll and "bd_roll_selected" or "ac_roll_selected")
for _,name in ipairs({"Pitch1Switch","Yaw1Switch","Pitch2Switch","Yaw2Switch"}) do set(name,0) end
set("TVCServoPower1Switch",1)
set("TVCServoPower2Switch",1)
sample("dap_ready_for_powered_flight")
keys("V06N20E")
waitPrompt(6,20,"imu_angles",10)
set("FDAISelectSwitch",0)
set("FDAISourceSwitch",1)
set("FDAIAttSetSwitch",1)
followIMU()
proc.wait_simdt(.5)
set("FDAIAttSetSwitch",0)
ship:set_panelswitch("GDCAlignButton",1,true)
for step=1,36 do
    followIMU()
    proc.wait_simdt(.25)
end
ship:set_panelswitch("GDCAlignButton",0)
set("FDAISourceSwitch",2)
set("FDAISelectSwitch",2)
keys("V37E00E")
proc.wait_simdt(1)
sample("gdc_alignment_complete")

-- Give R60 enough time for the largest attitude change before the burn.
while oapi.get_simtime()<waitUntil do
    if oapi.get_tacc()~=20 then oapi.set_tacc(20) end
    proc.wait_simdt(math.min(20,waitUntil-oapi.get_simtime()))
end
oapi.set_tacc(1)
proc.wait_simdt(2)
assert(math.floor(ship:get_agcerasable(0,63)/4096)%2==1,"Reference lost before P40")
keys("V37E40E")
waitPrompt(50,18,"awaiting_slew_prompt",40)
assert(sample("ready_for_slew")==40,"DSKY slew request outside P40")
output:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(4)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
