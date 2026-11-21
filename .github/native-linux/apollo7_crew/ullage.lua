local forward=ship:globalrot(_V(0,0,1))
local previousMode=ship:get_rcsmode()
ship:set_rcsmode(2)
local previousTime=oapi.get_simtime()
local impulse=0
while oapi.get_simtime()<ullageEnd do
    oapi.simulateimmediatekey(OAPI_KEY.NUMPAD6)
    proc.wait_frames(1)
    local now=oapi.get_simtime()
    impulse=impulse+ship:get_thrustvector().z*(now-previousTime)/ship:get_mass()
    previousTime=now
end
proc.wait_frames(2)
ship:set_rcsmode(previousMode)
local dot=vec.dotp(forward,ship:globalrot(_V(0,0,1)))
local drift=math.deg(math.acos(math.max(-1,math.min(1,dot))))
local ullageLog=assert(io.open("ullage.csv","w"))
ullageLog:write("axial_delta_v_m_s,pointing_drift_deg\n",string.format("%.6f,%.6f\n",impulse,drift))
ullageLog:close()
assert(impulse>.4 and impulse<3,"Forward ullage impulse outside limits")
assert(drift<3,"Ullage lost burn attitude")
reportState("ullage_complete")
