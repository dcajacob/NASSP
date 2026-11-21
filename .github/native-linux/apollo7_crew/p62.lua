-- initialMET and separationMET come from the actual retrofire target and output save.

local function checkpoint(name)
    oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
    proc.wait_frames(5)
    local file=assert(io.open("saved.scn","rb"))
    local state=file:read("*a")
    file:close()
    local output=assert(io.open(name..".scn","wb"))
    output:write(state)
    output:close()
end

proc.wait_simdt(1)
assert(ship:get_agcerasable(2,9)==62)
sample("p62_request_received")
for _,name in ipairs({"SECSLogic1Switch","SECSLogic2Switch","PyroArmASwitch","PyroArmBSwitch"}) do
    set(name,1)
end
oapi.set_tacc(4)
while initialMET+oapi.get_simtime()<separationMET-12 and ship:get_altitude(1)>190000 do
    proc.wait_simdt(8)
end
oapi.set_tacc(1)
while initialMET+oapi.get_simtime()<separationMET and ship:get_altitude(1)>190000 do
    proc.wait_simdt(.25)
end
sample("before_sm_sep")
-- Complete both CM RCS transfer circuits before pressing the separation switches.
for _,name in ipairs({"BatCPWRCircuitBraker","BatCtoBatBusACircuitBraker","BatCtoBatBusBCircuitBraker",
                     "RCSLogicMnACircuitBraker","RCSLogicMnBCircuitBraker"}) do set(name,1) end
set("MainBusTieBatAcSwitch",2)
set("MainBusTieBatBcSwitch",2)
set("CmSmSep1Switch",1,true)
set("CmSmSep2Switch",1,true)
proc.wait_simdt(2)
set("CmSmSep1Switch",0)
set("CmSmSep2Switch",0)
set("CautionWarningCMCSMSwitch",0)
set("RCSTrnfrSwitch",2,true)
proc.wait_simdt(3)
set("RCSTrnfrSwitch",1)
set("CMRCSLogicSwitch",0)
assert(present("SM")==1,"Service module did not separate")
sample("after_sm_sep")
checkpoint("rcs-transfer")
local transferFile=assert(io.open("rcs-transfer.scn","rb"))
local transfer=transferFile:read("*a")
transferFile:close()
assert(transfer:match("CMTRANSFERMOTOR1 1") and transfer:match("CMTRANSFERMOTOR2 1"),
       "Both CM RCS transfer relays must energize")
sample("cm_rcs_transfer_confirmed")

set("SCContSwitch",1)
set("CMCModeSwitch",2)
for _,axis in ipairs({"Roll","Pitch","Yaw"}) do set("BMAG"..axis.."Switch",2) end
for _,name in ipairs({"BdRollB1Switch","BdRollB2Switch","PitchC3Switch","PitchA4Switch",
                     "YawB3Switch","YawD4Switch"}) do set(name,2) end
for _,name in ipairs({"AcRollA1Switch","AcRollA2Switch","AcRollC1Switch","AcRollC2Switch",
                     "BdRollD1Switch","BdRollD2Switch","PitchA3Switch","PitchC4Switch",
                     "YawD3Switch","YawB4Switch"}) do set(name,1) end
for _,name in ipairs({"BDRollMnACircuitBraker","PitchMnACircuitBraker","YawMnACircuitBraker"}) do set(name,1) end
report:close()
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
