-- Release the main parachutes after actual surface contact and verify stable flotation.
local cm=assert(vessel.get_interface("AS-205"))
local out=assert(io.open("recovery.csv","w"))
out:write("elapsed,event,altitude,airspeed,latitude,longitude,ground_contact,main_attached\n")
local main=assert(vessel.get_handle("AS-205-MAINCHUTE"))
local attachment=assert(cm:get_attachmenthandle(false,1))
local function attached()
    return cm:get_attachmentstatus(attachment)==main
end
local function log(event)
    local p=cm:get_equpos()
    out:write(string.format("%.3f,%s,%.4f,%.4f,%.7f,%.7f,%s,%s\n",oapi.get_simtime(),
        event,cm:get_altitude(1),cm:get_airspeed(),math.deg(p.lat),math.deg(p.lng),
        tostring(cm:get_groundcontact()),tostring(attached())))
    out:flush()
end
proc.wait_frames(1)
assert(attached(),"Expected deployed mains still attached at splashdown")
while not cm:get_groundcontact() do
    assert(oapi.get_simtime()<60,"Capsule did not settle at the surface")
    proc.wait_frames(1)
end
log("water_contact")
proc.wait_simdt(15)
for _,name in ipairs({"BatBusAToPyroBusTieCircuitBraker","BatBusBToPyroBusTieCircuitBraker",
                      "SECSArmBatACircuitBraker","SECSArmBatBCircuitBraker",
                      "ELSBatACircuitBraker","ELSBatBCircuitBraker"}) do
    cm:set_panelswitch(name,1)
    assert(cm:get_panelswitch(name)==1,name)
end
cm:set_panelswitch("MainReleasePyroACircuitBraker",1)
cm:set_panelswitch("MainReleasePyroBCircuitBraker",1)
cm:set_panelswitch("MainReleaseSwitch",1,true)
proc.wait_simdt(6)
cm:set_panelswitch("MainReleaseSwitch",0)
assert(not attached(),"Main parachutes failed to detach")
log("mains_released")
proc.wait_simdt(60)
assert(cm:get_groundcontact() and cm:get_airspeed()<1,"Capsule did not settle after chute release")
log("settled_recovery")
out:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
