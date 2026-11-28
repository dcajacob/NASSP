-- Linear relative motion in the target's radial, along-track, orbit-normal
-- frame. Recompute from the actual S-IVB at each approach checkpoint.
local function correction(arrival)
    local r,v=rel()
    local radial,along,normal,n=frame(target)
    local x,y,z=vec.dotp(r,radial),vec.dotp(r,along),vec.dotp(r,normal)
    local dt=arrival-get()
    local a=n*dt
    local c,s=math.cos(a),math.sin(a)
    local xx,xy,yx,yy=s/n,2*(1-c)/n,-2*(1-c)/n,(4*s-3*a)/n
    local dx=-(4-3*c)*x
    local dy=-y-6*(s-a)*x
    local determinant=xx*yy-xy*yx
    local vx=(dx*yy-dy*xy)/determinant-n*y
    local vy=(dy*xx-dx*yx)/determinant+n*x
    local vz=(420-z*c)*n/s
    local want=vec.add(vec.add(vec.mul(radial,vx),vec.mul(along,vy)),vec.mul(normal,vz))
    return vec.sub(want,v)
end
controls()
dsky("Prog")
proc.wait_simdt(2.5)
dsky("KeyRel")
dsky("Reset")
for _,key in ipairs({"Verb","Three","Seven","Enter"}) do dsky(key) end
prompt(37,0,45)
for _,key in ipairs({"Zero","Zero","Enter"}) do dsky(key) end
local deadline=get()+45
while ship:get_agcerasable(2,9)~=0 do
    assert(get()<deadline,"CMC did not return to P00 after TPI")
    proc.wait_simdt(.5)
end
local _,_,_,mean_motion=frame(target)
local arrival=tig+math.rad(140)/mean_motion
assert(arrival-get()>500,"TPI flight leaves insufficient time for the approach")
for _,lead in ipairs({1050,500,160}) do
    coast(arrival-lead)
    local dv=correction(arrival)
    assert(vec.length(dv)<22,"Approach correction outside the rendezvous envelope")
    translate(dv,"approach_correction")
end
coast(arrival-30)
local _,v=rel()
translate(vec.mul(v,-1),"braking")
local separation,speed=rel()
assert(vec.length(separation)>150 and vec.length(separation)<850 and vec.length(speed)<.45,
       "S-IVB stationkeeping outside range or closing-rate limits")
event("stationkeeping")
local function hold(until_get)
    while get()<until_get do
        coast(math.min(until_get,get()+90))
        local r,v=rel()
        local _,_,normal=frame(target)
        local error=vec.sub(vec.mul(normal,420),r)
        local desired=vec.mul(error,1/300)
        local trim=vec.sub(desired,v)
        assert(vec.length(r)>150 and vec.length(r)<850,"Stationkeeping range outside corridor")
        if vec.length(trim)>.10 then translate(trim,"stationkeeping_trim") end
    end
end
-- The separation update is transmitted shortly after GET 30:10.
hold(108680)
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
local file=assert(io.open("saved.scn","rb"))
local raw=file:read("*a")
file:close()
assert(raw:match("\n  MCC_AP7MNV_purpose SEPARATION[\r\n]"),"Missing final separation PAD")
local departure=tonumber(raw:match("\n  MCC_AP7MNV_GETI ([%d.]+)"))
local x,y,z=raw:match("\n  MCC_AP7MNV_dV ([%d.%-]+) ([%d.%-]+) ([%d.%-]+)")
assert(departure>get() and tonumber(y)==0 and tonumber(z)==0,"Invalid final separation update")
hold(departure-35)
coast(departure)
local _,tangent=frame(ship)
translate(vec.mul(tangent,assert(tonumber(x))*.3048),"departure")
set("TransContrSwitch",0)
set("SCContSwitch",1)
set("CMCModeSwitch",0)
ship:set_rcsmode(0)
event("rendezvous_complete")
report:close()
