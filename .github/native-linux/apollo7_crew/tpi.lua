coast(tig-1100)
for _,key in ipairs({"Verb","Three","Seven","Enter","Four","One","Enter"}) do dsky(key) end
prompt(50,18,40)
set("SCContSwitch",1)
set("CMCModeSwitch",2)
dsky("Prog")
prompt(6,18,20)
prompt(50,18,tig-get()-80)
dsky("Enter")
assert(ship:get_agcerasable(2,9)==41,"TPI requires P41")
event("p41_ready")
-- Trim the actual thrust axis to the RTCC velocity direction as expressed
-- in the live orbit. P41 has already accepted the inertial slew.
proc.wait_simdt(tig-get()-250)
controls()
set("AttRateSwitch",1)
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("BMAG"..axis.."Switch",2) end
ship:set_rcsmode(1)
local function wanted_tpi()
    local radial,along,normal=frame(ship)
    return vec.add(vec.add(vec.mul(along,pad_dv[1]),vec.mul(normal,pad_dv[2])),vec.mul(radial,-pad_dv[3]))
end
local function rate(desired,actual,plus,minus)
    local diff=math.max(-.035,math.min(.035,desired))-actual
    if math.abs(diff)>.002 then oapi.simulateimmediatekey(OAPI_KEY[diff>0 and plus or minus]) end
end
while get()<tig do
    local d=vec.unit(wanted_tpi())
    local w=ship:get_angvel()
    local z=vec.dotp(d,ship:globalrot(_V(0,0,1)))
    rate(.18*math.atan2(vec.dotp(d,ship:globalrot(_V(0,1,0))),z),w.x,"NUMPAD2","NUMPAD8")
    rate(-.18*math.atan2(vec.dotp(d,ship:globalrot(_V(1,0,0))),z),w.y,"NUMPAD1","NUMPAD3")
    rate(0,w.z,"NUMPAD6","NUMPAD4")
    proc.wait_frames(1)
end
local wanted=wanted_tpi()
assert(vec.dotp(vec.unit(wanted),ship:globalrot(_V(0,0,1)))>math.cos(math.rad(5)),
       "TPI slew did not acquire the live RTCC direction")
controls()
translate(wanted,"tpi")
report:close()
