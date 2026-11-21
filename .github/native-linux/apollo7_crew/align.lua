-- Establish the CMC platform reference from two live sextant sightings in P51.
local ship=assert(vessel.get_interface("AS-205"))
local earth=ship:get_gravityref()
local sun=assert(oapi.get_gbody("Sun"))
local report=assert(io.open("alignment.csv","w"))
report:write("elapsed,event,star,shaft_deg,trunnion_deg,error_deg\n")
local function event(name,id,s,t,e)
    report:write(string.format("%.3f,%s,%02o,%.5f,%.5f,%.5f\n",oapi.get_simtime(),name,id or 0,s or 0,t or 0,e or 0))
    report:flush()
end
local function set(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value,name)
end
local function reference() return math.floor(ship:get_agcerasable(0,63)/4096)%2==1 end
local digits={"Zero","One","Two","Three","Four","Five","Six","Seven","Eight","Nine"}
local names={V="Verb",N="Noun",E="Enter",P="Prog",R="Reset",K="KeyRel",["+"]="Plus"}
local function keys(seq)
    for ch in seq:gmatch(".") do
        local key="DskySwitch"..(names[ch] or digits[tonumber(ch)+1])
        ship:set_panelswitch(key,1,true)
        proc.wait_simdt(.375)
        ship:set_panelswitch(key,0)
        proc.wait_simdt(.25)
    end
end
local function prompt(verb,noun,limit)
    local deadline=oapi.get_simtime()+limit
    while ship:get_agcerasable(2,1)~=verb or (noun and ship:get_agcerasable(2,2)~=noun) do
        assert(oapi.get_simtime()<deadline,"Missing P51 V"..verb.." N"..tostring(noun))
        proc.wait_simdt(.2)
    end
end
local function targetAngles(ray)
    local x=vec.dotp(ray,ship:globalrot(_V(1,0,0)))
    local y=vec.dotp(ray,ship:globalrot(_V(0,1,0)))
    local z=vec.dotp(ray,ship:globalrot(_V(0,0,1)))
    return math.deg(math.atan2(x,.5376381241*y+.8431756920*z)),
           math.deg(math.acos(math.min(1,math.max(-1,-.8431756920*y+.5376381241*z))))
end
local function choose(previous)
    local radial=vec.unit(ship:get_relativepos(earth))
    local sunward=vec.unit(vec.sub(oapi.get_globalpos(sun),ship:get_globalpos()))
    local best,score=nil,-math.huge
    for i,star in ipairs(stars) do
        local shaft,trun=targetAngles(star)
        local separation=previous and math.deg(math.acos(vec.dotp(star,stars[previous]))) or 45
        -- Require clear sight above Earth's limb, away from the Sun and
        -- within the 59-degree sextant mechanical stop for the whole mark.
        if trun>2 and trun<52 and vec.dotp(star,radial)>.02 and vec.dotp(star,sunward)<.85
            and separation>20 and separation<120 then
            local margin=52-trun+10*vec.dotp(star,radial)-.04*math.abs(shaft)
            if margin>score then best,score=i,margin end
        end
    end
    return best
end
local function center(i)
    local lastLog=-5
    local limit=oapi.get_simtime()+65
    repeat
        local wantedS,wantedT=targetAngles(stars[i])
        local s,t=ship:get_sextantangles()
        s,t=math.deg(s),math.deg(t)
        -- Shaft permits +/-270 degrees, so take the shorter reachable path.
        if wantedS-s>180 and wantedS-360>=-270 then wantedS=wantedS-360 end
        if wantedS-s< -180 and wantedS+360<=270 then wantedS=wantedS+360 end
        assert(wantedT<59,"Navigation star moved outside sextant travel")
        local ds,dt=wantedS-s,wantedT-t
        local weighted=ds*math.sin(math.rad(wantedT))
        local error=math.sqrt(weighted*weighted+dt*dt)
        if oapi.get_simtime()-lastLog>1 then
            event("centering",i,s,t,error)
            lastLog=oapi.get_simtime()
        end
        if error<.01 then
            set("OpticsHandcontrollerSwitch",0)
            event("star_centered",i,s,t,error)
            return
        end
        local shaft=math.abs(weighted)>math.abs(dt)
        local raw=shaft and ds or dt
        local dtick=.03125 -- fixed optical sampling interval at 1x
        local fast=(shaft and 19.5 or 10)*dtick
        local medium=(shaft and 2 or 1)*dtick
        local speed=math.abs(raw)>fast*.8 and 2 or (math.abs(raw)>medium*.8 and 1 or 0)
        set("ControllerSpeedSwitch",speed)
        set("OpticsHandcontrollerSwitch",shaft and (ds>0 and 1 or 2) or (dt>0 and 4 or 3))
        proc.wait_frames(1)
    until oapi.get_simtime()>limit
    set("OpticsHandcontrollerSwitch",0)
    error("Could not center star "..i)
end
local function mark(previous)
    prompt(51,nil,30)
    local deadline=oapi.get_simtime()+600
    local i=choose(previous)
    while not i do
        assert(oapi.get_simtime()<deadline,"No illuminated-sky clearance for a P51 mark")
        proc.wait_simdt(2)
        i=choose(previous)
    end
    center(i)
    ship:set_panelswitch("OpticsMarkButton",1,true)
    proc.wait_simdt(.09)
    ship:set_panelswitch("OpticsMarkButton",0)
    prompt(50,25,20)
    keys("P")
    prompt(1,71,20)
    keys(string.format("V21E%05oE",i))
    proc.wait_simdt(1)
    keys("P")
    event("star_marked",i)
    return i
end
local function align()
    set("GNPowerOpticsSwitch",1)
    set("OpticsZeroSwitch",1)
    proc.wait_simdt(22)
    set("OpticsZeroSwitch",0)
    set("OpticsModeSwitch",0)
    set("ControllerCouplingSwitch",1)
    keys("KRV41N20E")
    prompt(21,22,20)
    keys("+00000E+00000E+00000E")
    proc.wait_simdt(22)
    keys("V40N20E")
    proc.wait_simdt(20)
    keys("V37E51E")
    prompt(50,25,30)
    proc.wait_simdt(1)
    keys("P")
    local first=mark(nil)
    mark(first)
    prompt(6,5,35)
    proc.wait_simdt(.75)
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(4)
    local f=assert(io.open("saved.scn","rb"))
    local dsky=assert(f:read("*a"):match("DSKY_BEGIN[^_].-DSKY_END"))
    f:close()
    local difference=assert(tonumber(dsky:match(" R1%s+([+-]%d+)")))/100
    event("star_separation_check",nil,nil,nil,difference)
    assert(math.abs(difference)<=.03,"Sextant marks disagree on star separation")
    keys("P")
    prompt(37,0,25)
    proc.wait_simdt(.75)
    keys("00E")
    proc.wait_simdt(3)
    assert(ship:get_agcerasable(2,9)==0 and reference(),"P51 failed to restore the reference")
    set("OpticsZeroSwitch",1)
    set("GNPowerOpticsSwitch",0)
end
proc.wait_simdt(2)
assert(ship:get_agcerasable(2,9)==0,"Expected P00 before final alignment")
while oapi.get_simtime()<coast_seconds do
    oapi.set_tacc(40)
    proc.wait_simdt(math.min(coast_seconds-oapi.get_simtime(),60))
end
oapi.set_tacc(1)
proc.wait_simdt(2)
if not reference() then align() end
event("platform_reference_ready")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
