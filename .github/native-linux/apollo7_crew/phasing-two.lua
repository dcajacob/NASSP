-- Phasing 2 is an optional, along-track RCS maneuver on the voice PAD.
local ship=assert(vessel.get_interface("AS-205"))
local earth=ship:get_gravityref()
local report=assert(io.open("phasing-two.csv","w"))
report:write("get,event,pointing_deg,target_m_s,measured_m_s,vector_error_m_s\n")
local function get() return initial_get+oapi.get_simtime() end
local function set(name,value)
    ship:set_panelswitch(name,value)
    assert(ship:get_panelswitch(name)==value,name)
end
local function along()
    local r=vec.unit(ship:get_relativepos(earth))
    local v=ship:get_relativevel(earth)
    return vec.unit(vec.sub(v,vec.mul(r,vec.dotp(r,v))))
end
local function desired() return vec.mul(along(),target_dv<0 and -1 or 1) end
local function clamp(x,lo,hi) return math.max(lo,math.min(hi,x)) end
local function angle(d)
    return math.deg(math.acos(clamp(vec.dotp(d,ship:globalrot(_V(0,0,1))),-1,1)))
end
local function stick(command,rate,plus,minus)
    if math.abs(command-rate)>.0025 then
        oapi.simulateimmediatekey(OAPI_KEY[command>rate and plus or minus])
    end
end
local function steer(d)
    local x=vec.dotp(d,ship:globalrot(_V(1,0,0)))
    local y=vec.dotp(d,ship:globalrot(_V(0,1,0)))
    local z=vec.dotp(d,ship:globalrot(_V(0,0,1)))
    if z<-.8 and math.abs(x)+math.abs(y)<.1 then x=.15 end
    local w=ship:get_angvel()
    stick(clamp(.18*math.atan2(y,z),-.033,.033),w.x,"NUMPAD2","NUMPAD8")
    stick(clamp(-.18*math.atan2(x,z),-.033,.033),w.y,"NUMPAD1","NUMPAD3")
    stick(0,w.z,"NUMPAD6","NUMPAD4")
end
local function record(name,d,impulse,error)
    report:write(string.format("%.3f,%s,%.4f,%.5f,%.5f,%.5f\n",
        get(),name,angle(d),target_dv,impulse or 0,error or 0))
    report:flush()
end
while get()<tig-540 do
    oapi.set_tacc(40)
    proc.wait_simdt(math.min(90,tig-540-get()))
end
oapi.set_tacc(1)
set("SCContSwitch",0)
set("CMCModeSwitch",0)
set("AttRateSwitch",1)
set("AttDeadbandSwitch",0)
set("LimitCycleSwitch",0)
ship:set_rcsmode(1)
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("ManualAtt"..axis.."Switch",1) end
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("BMAG"..axis.."Switch",2) end
record("slew_start",desired())
while get()<tig do
    steer(desired())
    proc.wait_frames(1)
end
local direction=desired()
record("before_burn",direction)
assert(angle(direction)<3,"Second phasing slew missed live PAD direction")
-- Power both pitch and yaw jet pairs. RATE 2 and LOW retain SCS damping
-- while the hand controller commands forward translation.
for _,axis in ipairs({"Pitch","Yaw"}) do
    for _,bus in ipairs({"MnA","MnB"}) do set(axis..bus.."CircuitBraker",1) end
end
for name,bus in pairs({PitchA3Switch=0,PitchC3Switch=2,PitchA4Switch=2,PitchC4Switch=0,
                       YawB3Switch=2,YawD3Switch=0,YawB4Switch=0,YawD4Switch=2}) do set(name,bus) end
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("BMAG"..axis.."Switch",1) end
set("AttRateSwitch",0)
set("THCRotary",1)
set("TransContrSwitch",1)
ship:set_rcsmode(2)
local acc=_V(0,0,0)
local function integrate()
    local thrust=ship:globalrot(ship:get_thrustvector())
    acc=vec.add(acc,vec.mul(thrust,oapi.get_simstep()/ship:get_mass()))
end
while vec.dotp(acc,direction)<math.abs(target_dv)-.012 do
    assert(get()<tig+duration*2+5,"Insufficient RCS impulse")
    oapi.simulateimmediatekey(OAPI_KEY.NUMPAD6)
    proc.wait_frames(1)
    integrate()
end
for i=1,16 do proc.wait_frames(1); integrate() end
local measured=vec.dotp(acc,direction)
local error=vec.length(vec.sub(acc,vec.mul(direction,math.abs(target_dv))))
record("cutoff",direction,measured,error)
assert(error<.15,"Second phasing impulse differs from RTCC vector")
set("TransContrSwitch",0)
set("CMCModeSwitch",0)
set("SCContSwitch",1)
ship:set_rcsmode(0)
record("phasing_two_complete",direction,measured,error)
report:close()
