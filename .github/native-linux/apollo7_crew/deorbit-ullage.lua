-- Once any SM quad is exhausted, the remaining axial jets exert an uncompensated
-- moment. Settle early, reacquire the commanded attitude with the CM jets, and
-- apply a short settling pulse immediately before the P40 authorization.
local impulse=0
local function directPulse(seconds)
    local untilTime=oapi.get_simtime()+seconds
    set("DirectUllMnACircuitBraker",1)
    set("DirectUllMnBCircuitBraker",1)
    ship:set_panelswitch("DirectUllageButton",1,true)
    while oapi.get_simtime()<untilTime do
        local before=oapi.get_simtime()
        proc.wait_frames(1)
        impulse=impulse+ship:get_thrustvector().z*(oapi.get_simtime()-before)/ship:get_mass()
    end
    set("DirectUllageButton",0)
end

local depleted=false
for i=1,4 do
    if ship:get_propellantmass(ship:get_propellanthandle(i))<1 then depleted=true end
end
oapi.set_tacc(4)
at(-620,"before_final_retrofire_aim")
oapi.set_tacc(1)
pressurizeCmRcs()
local nextEvent=depleted and -260 or -85
assert(aimWithCmRcs(targetZ,targetY,timeToIgnition+nextEvent-5,slewTelemetry),"R60 slew missed final trim")
reportState("r60_final_aim")
while oapi.get_simtime()<timeToIgnition+nextEvent do
    proc.wait_simdt(math.min(20,timeToIgnition+nextEvent-oapi.get_simtime()))
    if vec.dotp(ship:globalrot(_V(0,0,1)),targetZ)<math.cos(math.rad(1.8)) then
        assert(aimWithCmRcs(targetZ,targetY,timeToIgnition+nextEvent+20,slewTelemetry),"R60 hold failed")
    end
end
if depleted then
    directPulse(13)
    reportState("depleted_quad_settling")
    assert(aimWithCmRcs(targetZ,targetY,timeToIgnition-40,slewTelemetry),"Unable to reacquire R60 after settling")
    reportState("r60_reacquired_after_settling")
    -- Keep the CM jets in the attitude loop until transfer back to SM.
    -- A small residual body rate over the last two minutes can carry the
    -- thrust axis several degrees off the retrofire direction.
    while oapi.get_simtime()<timeToIgnition-14 do
        aimWithCmRcs(targetZ,targetY,timeToIgnition-14,slewTelemetry)
        proc.wait_frames(1)
    end
end
