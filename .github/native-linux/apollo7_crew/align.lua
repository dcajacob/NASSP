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
local function choose(previous,maxTrunnion)
    local radial=vec.unit(ship:get_relativepos(earth))
    local sunward=vec.unit(vec.sub(oapi.get_globalpos(sun),ship:get_globalpos()))
    local best,score=nil,-math.huge
    for i,star in ipairs(stars) do
        local shaft,trun=targetAngles(star)
        local separation=previous and math.deg(math.acos(vec.dotp(star,stars[previous]))) or 45
        -- Require clear sight above Earth's limb, away from the Sun and
        -- within the 59-degree sextant mechanical stop for the whole mark.
        if trun>2 and trun<maxTrunnion and vec.dotp(star,radial)>.02 and vec.dotp(star,sunward)<.85
            and separation>20 and separation<120 then
            local margin=52-trun+10*vec.dotp(star,radial)-.04*math.abs(shaft)
            if margin>score then best,score=i,margin end
        end
    end
    return best
end
-- If the optics are pointed into Earth, use the rotational hand controller
-- to bring a visible catalog star into the sextant field before searching again.
local function orient(i)
    local optics=_V(0,-.8431756920,.5376381241)
    local axes={{"Pitch","x",OAPI_KEY.NUMPAD2,OAPI_KEY.NUMPAD8},
                {"Yaw","y",OAPI_KEY.NUMPAD1,OAPI_KEY.NUMPAD3},
                {"Roll","z",OAPI_KEY.NUMPAD6,OAPI_KEY.NUMPAD4}}
    set("SCContSwitch",0)
    set("AttRateSwitch",0)
    for _,axis in ipairs(axes) do set("ManualAtt"..axis[1].."Switch",2) end
    ship:set_rcsmode(1)
    local deadline=oapi.get_simtime()+225
    repeat
        local function project(v) return vec.dotp(ship:globalrot(v),stars[i]) end
        local body=_V(project(_V(1,0,0)),project(_V(0,1,0)),project(_V(0,0,1)))
        local angle=math.acos(math.min(1,math.max(-1,vec.dotp(body,optics))))
        local rate=ship:get_angvel()
        if angle<math.rad(20) and vec.length(rate)<math.rad(.10) then break end
        local goal=_V(0,0,0)
        if angle>math.rad(15) then
            local axis=vec.crossp(optics,body)
            if vec.length(axis)<1e-6 then axis=_V(1,0,0) end
            goal=vec.mul(vec.unit(axis),-math.min(math.rad(1.35),.23*(angle-math.rad(14))))
        end
        local err=vec.sub(goal,rate)
        local largest=axes[1]
        for _,a in ipairs(axes) do
            if math.abs(err[a[2]])>math.abs(err[largest[2]]) then largest=a end
        end
        local value=err[largest[2]]
        if math.abs(value)>math.rad(.027) then
            oapi.simulateimmediatekey(value>0 and largest[3] or largest[4])
        end
        proc.wait_frames(1)
    until oapi.get_simtime()>deadline
    ship:set_rcsmode(0)
    for _,axis in ipairs(axes) do set("ManualAtt"..axis[1].."Switch",1) end
    for _,axis in ipairs(axes) do set("BMAG"..axis[1].."Switch",2) end
    set("AttDeadbandSwitch",0)
    set("LimitCycleSwitch",0)
    proc.wait_simdt(3)
end
local function center(i)
    local lastS,lastT,lastFrame=nil,nil,nil
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
        if error<.014 then
            set("OpticsHandcontrollerSwitch",0)
            event("star_centered",i,s,t,error)
            return
        end
        -- Lead a moving star by one controller cycle, while accepting a mark
        -- only on the measured line of sight.
        if lastS then
            ds=ds+(wantedS-lastS+180)%360-180
            dt=dt+wantedT-lastT
            weighted=ds*math.sin(math.rad(wantedT))
        end
        lastS,lastT=wantedS,wantedT
        local shaft=math.abs(weighted)>math.abs(dt)
        local raw=shaft and ds or dt
        local now=oapi.get_simtime()
        local dtick=lastFrame and (now-lastFrame) or .03125
        lastFrame=now
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
    local i=choose(previous,52)
    if not i then
        local candidate=assert(choose(previous,180),"No navigation star clear of Earth and the Sun")
        event("maneuver_to_visible_star",candidate)
        orient(candidate)
        i=assert(choose(previous,56),"RCS maneuver failed to put a star in view")
    end
    event("star_selected",i)
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
    event("coarse_alignment")
    set("GNPowerOpticsSwitch",1)
    set("OpticsZeroSwitch",1)
    proc.wait_simdt(22)
    set("OpticsZeroSwitch",0)
    set("OpticsModeSwitch",0)
    set("ControllerCouplingSwitch",1)
    if prepare_launch_optics then
        -- The original launch starts with the telescope cover fitted. Slew
        -- the telescope through +150 degrees, then return both optics to zero.
        set("ControllerSpeedSwitch",2)
        set("OpticsHandcontrollerSwitch",1)
        local deadline=oapi.get_simtime()+35
        while math.deg(ship:get_sextantangles())<165 do
            assert(oapi.get_simtime()<deadline,"Optics cover slew failed")
            proc.wait_frames(1)
        end
        proc.wait_simdt(2)
        set("OpticsHandcontrollerSwitch",0)
        set("OpticsZeroSwitch",1)
        proc.wait_simdt(25)
        set("OpticsZeroSwitch",0)
        oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
        proc.wait_frames(5)
        local f=assert(io.open("saved.scn","rb"))
        local raw=f:read("*a")
        f:close()
        assert(raw:match("OPTICSCOVERED 0"),"Telescope cover did not release")
        event("optics_cover_released")
        set("SCContSwitch",0)
        set("AttRateSwitch",0)
        set("LimitCycleSwitch",0)
        set("AttDeadbandSwitch",0)
        local axes={{"Pitch","x","NUMPAD2","NUMPAD8"},{"Yaw","y","NUMPAD1","NUMPAD3"},{"Roll","z","NUMPAD6","NUMPAD4"}}
        for _,axis in ipairs(axes) do
            set("ManualAtt"..axis[1].."Switch",2)
            set("BMAG"..axis[1].."Switch",2)
        end
        ship:set_rcsmode(1)
        deadline=oapi.get_simtime()+100
        while vec.length(ship:get_angvel())>math.rad(.035) do
            assert(oapi.get_simtime()<deadline,"Cannot stabilize optics sighting")
            local w=ship:get_angvel()
            local axis=axes[1]
            for _,a in ipairs(axes) do if math.abs(w[a[2]])>math.abs(w[axis[2]]) then axis=a end end
            oapi.simulateimmediatekey(OAPI_KEY[w[axis[2]]>0 and axis[4] or axis[3]])
            proc.wait_frames(1)
        end
        for _,axis in ipairs(axes) do
            set("ManualAtt"..axis[1].."Switch",1)
            set("BMAG"..axis[1].."Switch",1)
        end
        ship:set_rcsmode(0)
        event("sighting_rates_trimmed")
    end
    keys("KRV41N20E")
    prompt(21,22,20)
    keys("+00000E+00000E+00000E")
    proc.wait_simdt(22)
    keys("V40N20E")
    proc.wait_simdt(20)
    event("coarse_drive_complete")
    keys("V37E51E")
    prompt(50,25,30)
    proc.wait_simdt(1)
    keys("P")
    event("p51_first_mark_request")
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
set("SCContSwitch",1)
event("platform_reference_ready")
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
