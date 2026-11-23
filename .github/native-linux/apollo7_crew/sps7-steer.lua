-- The CMC holds attitude during four-jet THC ullage. Use the powered B
-- valve feeds, then return to SCS for manual ignition and EMS cutoff.
for _,jet in ipairs({"PitchA3","PitchA4","PitchC3","PitchC4","YawB3","YawB4","YawD3","YawD4"}) do
    set(jet.."Switch",0)
end
set("SCContSwitch",1)
set("CMCModeSwitch",2)

local reference=vec.unit(goal)
local function steer()
    if vec.length(vec.sub(goal,accumulated))>12 then reference=remainingDirection() end
    local rates=ship:get_angvel()
    local pitch=.8*vec.dotp(reference,ship:globalrot(_V(0,1,0)))-rates.x
    local yaw=-.8*vec.dotp(reference,ship:globalrot(_V(1,0,0)))-rates.y
    if math.abs(pitch)>math.abs(yaw) and math.abs(pitch)>math.rad(.035) then
        oapi.simulateimmediatekey(pitch>0 and OAPI_KEY.NUMPAD2 or OAPI_KEY.NUMPAD8)
    elseif math.abs(yaw)>math.rad(.035) then
        oapi.simulateimmediatekey(yaw>0 and OAPI_KEY.NUMPAD1 or OAPI_KEY.NUMPAD3)
    end
end
local function steerUntil(deadline)
    while oapi.get_simtime()<deadline do
        steer()
        proc.wait_frames(1)
    end
end
