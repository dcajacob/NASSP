-- Ground TIG and LVLH velocity components are taken from this flight's PAD.
local ship=vessel.get_focusinterface()
local report=assert(io.open("p30.csv","w"))
report:write("phase,noun,r1,r2,r3\n")
local function keys(sequence)
    local digits={"Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine"}
    local names={V="Verb",N="Noun",E="Enter",P="Prog",["+"]="Plus",["-"]="Minus"}
    for char in sequence:gmatch(".") do
        local switch="DskySwitch"..(names[char] or digits[tonumber(char)+1])
        ship:set_panelswitch(switch,1,true)
        proc.wait_simdt(.375)
        ship:set_panelswitch(switch,0)
        proc.wait_simdt(.25)
    end
end
local function waitPrompt(verb,noun)
    local deadline=oapi.get_simtime()+150
    while ship:get_agcerasable(2,1)~=verb or ship:get_agcerasable(2,2)~=noun do
        assert(oapi.get_simtime()<deadline,"Missing DSKY V"..verb.." N"..noun)
        proc.wait_simdt(.5)
    end
end
local function registers(noun,phase)
    waitPrompt(6,noun)
    proc.wait_simdt(1)
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local file=assert(io.open("saved.scn","rb"))
    local raw=file:read("*a")
    file:close()
    local display=assert(raw:match("\nDSKY_BEGIN\r?\n(.-)DSKY_END"))
    local result={}
    for i=1,3 do
        local value=assert(display:match(" R"..i.." +([+-]?%d+)"),"Blank DSKY register R"..i)
        result[i]=tonumber(value)
    end
    report:write(string.format("%s,%d,%d,%d,%d\n",phase,noun,unpack(result)))
    report:flush()
    return result
end
proc.wait_simdt(2)
assert(ship:get_agcerasable(2,9)==0,"P30 requires CMC in P00")
keys("V37E30E")
if manual_entry then
    waitPrompt(6,33)
    local cs=math.floor(tig*100+.5)
    keys(string.format("V25N33E+%05dE+%05dE+%05dE",math.floor(cs/360000),math.floor(cs/6000)%60,cs%6000))
end
local time=registers(33,"ignition_time")
assert(math.abs(time[1]*3600+time[2]*60+time[3]/100-tig)<=.03,"N33 disagrees with MCC TIG")
keys("P")
if manual_entry then
    waitPrompt(6,81)
    local function tenths(v) return v<0 and math.ceil(v*10-.5) or math.floor(v*10+.5) end
    keys(string.format("V25N81E%+06dE%+06dE%+06dE",tenths(deltaV[1]),tenths(deltaV[2]),tenths(deltaV[3])))
end
local components=registers(81,"delta_v")
for i=1,3 do
    assert(math.abs(components[i]/10-deltaV[i])<=.15,"N81 disagrees with MCC delta-v")
end
keys("P")
waitPrompt(6,42)
keys("P")
waitPrompt(16,45)
keys("P")
waitPrompt(37,0)
keys("00E")
proc.wait_simdt(6)
assert(ship:get_agcerasable(2,9)==0,"P30 failed to return to P00")
report:write("p30_pad_verified,,,,\n")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
