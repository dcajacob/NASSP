-- Fly TPI on the current PAD, then use relative navigation for the approach.
local ship=assert(vessel.get_interface("AS-205"))
local target=assert(vessel.get_interface("AS-205-S4BSTG"))
local earth=ship:get_gravityref()
local report=assert(io.open("rendezvous.csv","w"))
report:write("get,event,range_m,relative_speed_m_s,target_dv_m_s,residual_m_s\n")
local function get() return start_get+oapi.get_simtime() end
local function set(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value,name)
end
local function rel()
    return vec.sub(ship:get_relativepos(earth),target:get_relativepos(earth)),
           vec.sub(ship:get_relativevel(earth),target:get_relativevel(earth))
end
local function event(label,mag,err)
    local r,v=rel()
    report:write(string.format("%.3f,%s,%.3f,%.4f,%.5f,%.5f\n",
        get(),label,vec.length(r),vec.length(v),mag or 0,err or 0))
    report:flush()
end
local function coast(until_get)
    while get()<until_get do
        oapi.set_tacc(math.min(20,math.max(1,(until_get-get())/4)))
        proc.wait_simdt(math.min(10,until_get-get()))
    end
    oapi.set_tacc(1)
end
local function frame(object)
    local r=object:get_relativepos(earth)
    local v=object:get_relativevel(earth)
    local radial=vec.unit(r)
    local along=vec.unit(vec.sub(v,vec.mul(radial,vec.dotp(v,radial))))
    local normal=vec.unit(vec.crossp(radial,along))
    return radial,along,normal,vec.length(vec.crossp(r,v))/vec.dotp(r,r)
end
local function translate(wanted,label)
    local applied=_V(0,0,0)
    local mag=vec.length(wanted)
    local deadline=get()+40+mag*55
    local next_log=get()
    local trace=assert(io.open("translation.csv","a"))
    local function tick()
        proc.wait_frames(1)
        local force=ship:globalrot(ship:get_thrustvector())
        applied=vec.add(applied,vec.mul(force,oapi.get_simstep()/ship:get_mass()))
    end
    ship:set_rcsmode(2)
    while vec.length(vec.sub(wanted,applied))>.045 do
        assert(get()<deadline,"Insufficient translation authority for "..label)
        local e=vec.sub(wanted,applied)
        local x=vec.dotp(e,ship:globalrot(_V(1,0,0)))
        local y=vec.dotp(e,ship:globalrot(_V(0,1,0)))
        local z=vec.dotp(e,ship:globalrot(_V(0,0,1)))
        local key
        if math.abs(x)>=math.max(math.abs(y),math.abs(z)) then key=x>0 and "NUMPAD3" or "NUMPAD1"
        elseif math.abs(y)>=math.abs(z) then key=y>0 and "NUMPAD2" or "NUMPAD8"
        else key=z>0 and "NUMPAD6" or "NUMPAD9" end
        oapi.simulateimmediatekey(OAPI_KEY[key])
        tick()
        if get()>=next_log then
            local f=ship:get_thrustvector()
            trace:write(string.format("%.3f,%s,%s,%.4f,%.4f,%.4f,%.2f,%.2f,%.2f\n",
                get(),label,key,x,y,z,f.x,f.y,f.z))
            trace:flush()
            next_log=get()+2
        end
    end
    trace:close()
    for i=1,12 do tick() end
    local error=vec.length(vec.sub(wanted,applied))
    event(label,mag,error)
    assert(error<.13,"RCS impulse disagrees with "..label)
end
local function controls()
    set("SCContSwitch",0)
    set("TransContrSwitch",1)
    set("THCRotary",1)
    set("LimitCycleSwitch",0)
    set("AttRateSwitch",0)
    for _,axis in ipairs({"Pitch","Yaw","Roll"}) do
        set("ManualAtt"..axis.."Switch",1)
        set("BMAG"..axis.."Switch",1)
    end
    for _,jet in ipairs({"PitchA3","PitchA4","PitchC3","PitchC4","YawB3","YawB4","YawD3","YawD4",
                         "AcRollA1","AcRollA2","AcRollC1","AcRollC2","BdRollB1","BdRollB2","BdRollD1","BdRollD2"}) do
        set(jet.."Switch",2)
    end
end
local function dsky(label)
    ship:set_panelswitch("DskySwitch"..label,1,true)
    proc.wait_simdt(.375)
    ship:set_panelswitch("DskySwitch"..label,0)
    proc.wait_simdt(.375)
end
local function prompt(verb,noun,timeout)
    local end_get=get()+timeout
    while ship:get_agcerasable(2,1)~=verb or ship:get_agcerasable(2,2)~=noun do
        assert(get()<end_get,"P41 missed DSKY prompt "..verb.."/"..noun)
        proc.wait_simdt(.375)
    end
end
