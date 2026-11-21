-- Integrate measured thrust in an inertial frame, including ullage. Use the
-- PAD velocity axes at TIG (along track, south-normal, down) for readback.
-- In Orbiter's left-handed frame R cross V points along positive LVLH Y.
local earthRef=ship:get_gravityref()
local r=ship:get_relativepos(earthRef)
local v=ship:get_relativevel(earthRef)
local dt=timeToIgnition-oapi.get_simtime()
local gravity=ship:globalrot(assert(ship:get_weightvector()))
local acceleration=vec.mul(gravity,1/ship:get_mass())
local rTig=vec.add(vec.add(r,vec.mul(v,dt)),vec.mul(acceleration,.5*dt*dt))
local yAxis=vec.unit(vec.crossp(r,v))
local zAxis=vec.mul(vec.unit(rTig),-1)
local xAxis=vec.unit(vec.crossp(zAxis,yAxis))
local goal=vec.add(vec.add(vec.mul(xAxis,padLVLH[1]),vec.mul(yAxis,padLVLH[2])),
                   vec.mul(zAxis,padLVLH[3]))
local accumulated=_V(0,0,0)
local function integrateThrust()
    local prev=oapi.get_simtime()
    while true do
        proc.wait_frames(1)
        local now=oapi.get_simtime()
        local thrust=ship:globalrot(ship:get_thrustvector())
        accumulated=vec.add(accumulated,vec.mul(thrust,(now-prev)/ship:get_mass()))
        prev=now
    end
end
proc.bg(integrateThrust)
local function remainingDirection()
    return vec.unit(vec.sub(goal,accumulated))
end
