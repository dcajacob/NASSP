-- Cross-check the R60 attitude against the live PAD during the manual SCS
-- checklist. Resolve the inertial burn direction in the LVLH frame at TIG.
local function burnDirection()
    local earth=ship:get_gravityref()
    local r=ship:get_relativepos(earth)
    local v=ship:get_relativevel(earth)
    local radial=vec.unit(r)
    local normal=vec.unit(vec.crossp(r,v))
    local along=vec.unit(vec.crossp(normal,radial))
    local angle=vec.length(vec.crossp(r,v))/vec.dotp(r,r)*(timeToIgnition-oapi.get_simtime())
    local down=vec.mul(vec.add(vec.mul(radial,math.cos(angle)),vec.mul(along,math.sin(angle))),-1)
    local forward=vec.unit(vec.crossp(down,normal))
    return vec.unit(vec.add(vec.add(vec.mul(forward,padLVLH[1]),vec.mul(normal,padLVLH[2])),
                            vec.mul(down,padLVLH[3])))
end
local pointing=assert(io.open("pointing.csv","w"))
pointing:write("time_to_tig_s,error_deg,rate_deg_s,engine_deg,pitch_bias_deg,yaw_bias_deg\n")
local function recordPointing()
    local z=vec.dotp(burnDirection(),ship:globalrot(_V(0,0,1)))
    local err=math.deg(math.acos(math.min(1,math.max(-1,z))))
    local nozzle=ship:get_thrusterdir(engine)
    local dot=vec.dotp(burnDirection(),ship:globalrot(nozzle))
    pointing:write(string.format("%.3f,%.4f,%.4f,%.4f,%.4f,%.4f\n",timeToIgnition-oapi.get_simtime(),
        err,math.deg(vec.length(ship:get_angvel())),math.deg(math.acos(math.min(1,math.max(-1,dot)))),
        math.deg(math.atan2(nozzle.y,nozzle.z)),math.deg(math.atan2(nozzle.x,nozzle.z))))
    pointing:flush()
    return math.deg(math.acos(math.min(1,math.max(-1,dot))))
end
local function drive(angle,rate,plus,minus)
    local wanted=math.max(-.04,math.min(.04,.25*angle))
    if math.abs(wanted-rate)>.0012 then
        oapi.simulateimmediatekey(OAPI_KEY[wanted>rate and plus or minus])
    end
end
local function trimUntil(offset)
    while oapi.get_simtime()<timeToIgnition+offset do
        local goal=burnDirection()
        local rates=ship:get_angvel()
        local z=vec.dotp(goal,ship:globalrot(_V(0,0,1)))
        local nozzle=ship:get_thrusterdir(engine)
        local pitch=math.atan2(vec.dotp(goal,ship:globalrot(_V(0,1,0))),z)-math.atan2(nozzle.y,nozzle.z)
        local yaw=math.atan2(vec.dotp(goal,ship:globalrot(_V(1,0,0))),z)-math.atan2(nozzle.x,nozzle.z)
        drive(pitch,rates.x,"NUMPAD2","NUMPAD8")
        drive(-yaw,rates.y,"NUMPAD1","NUMPAD3")
        drive(0,rates.z,"NUMPAD6","NUMPAD4")
        proc.wait_frames(1)
    end
end
recordPointing()
set("SCContSwitch",0)
set("AttRateSwitch",1)
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("BMAG"..axis.."Switch",2) end
ship:set_rcsmode(1)
trimUntil(-61)
recordPointing()
