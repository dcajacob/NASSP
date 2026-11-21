-- Use the PAD velocity axes at TIG (along track, south-normal, down).
-- In Orbiter's left-handed frame R cross V points along positive LVLH Y.
local earthRef=ship:get_gravityref()
local r=ship:get_relativepos(earthRef)
local v=ship:get_relativevel(earthRef)
local dt=timeToIgnition-oapi.get_simtime()
local rTig=vec.add(r,vec.mul(v,dt))
local yAxis=vec.unit(vec.crossp(r,v))
local zAxis=vec.mul(vec.unit(rTig),-1)
local xAxis=vec.unit(vec.crossp(zAxis,yAxis))
local goal=vec.add(vec.add(vec.mul(xAxis,padLVLH[1]),vec.mul(yAxis,padLVLH[2])),
                   vec.mul(zAxis,padLVLH[3]))
local accumulated=vec.mul(forward,impulse)
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
