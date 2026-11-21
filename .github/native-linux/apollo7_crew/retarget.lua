-- Use the CAPCOM repeat-update option to ask the RTCC for a new PUGS PAD.
-- Its targeting routine searches for a different burn longitude if required.
local ship=vessel.get_focusinterface()
proc.wait_simdt(2)
assert(ship:get_agcerasable(2,9)==0)
oapi.simulatebufferedkey(OAPI_KEY.TAB)
proc.wait_simdt(2)
oapi.simulatebufferedkey(0x04)
local deadline=oapi.get_simtime()+180
local report=assert(io.open("retarget.csv","w"))
report:write("phase,tig,burn_s,fuel_kg,remaining_kg\n")
repeat
    proc.wait_simdt(2)
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local f=assert(io.open("saved.scn","rb"))
    local scn=f:read("*a")
    f:close()
    if scn:match("MCC_MissionState 107\r?\n  MCC_SubState 2\r?\n")
        and scn:match("MCC_AP7MNV_purpose SPS%-5 / PUGS") then
        local duration=assert(tonumber(scn:match("MCC_AP7MNV_burntime ([^\r\n]+)")))
        local tig=assert(tonumber(scn:match("MCC_AP7MNV_GETI ([^\r\n]+)")))
        local fuel=assert(tonumber(scn:match("SPSPROPELLANT_BEGIN.-\n  PROPELLANTMASS ([^\r\n]+)")))
        local reserve=fuel-duration*29.606
        if reserve>=700 then
            report:write(string.format("recovery_reserve_verified,%.3f,%.3f,%.3f,%.3f\n",tig,duration,fuel,reserve))
            report:close()
            oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
            return
        end
    end
until oapi.get_simtime()>=deadline
error("MCC could not supply an SPS-5 target with 700 kg of recovery reserve")
