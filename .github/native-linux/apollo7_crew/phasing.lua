local ship=vessel.get_focusinterface()
local earth=ship:get_gravityref()
local target=oapi.get_objhandle("AS-205-S4BSTG")
assert(target, "Separated S-IVB missing")
local report=assert(io.open("phasing-flight.csv","w"))
report:write("met,marker,angle,roll_error,wx,wy,wz,retro_dv,sm_rcs_fuel,periapsis,apoapsis,range,ems,irq\n")
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function clamp(n,lo,hi) return math.max(lo,math.min(hi,n)) end
local function met() return startMET+oapi.get_simtime() end
local function switch(n,s,hold) ship:set_panelswitch(n,s,hold) end
local function key(n) oapi.simulateimmediatekey(OAPI_KEY[n]) end
local function majorMode(first,second)
    for _, label in ipairs({"Verb","Three","Seven","Enter",first,second,"Enter"}) do
        local name="DskySwitch"..label
        switch(name,1,true)
        proc.wait_simdt(0.35)
        switch(name,0)
        proc.wait_simdt(0.25)
    end
end
local function angles()
    local velocity=vec.unit(ship:get_relativevel(earth))
    local forward=ship:globalrot(_V(0,0,1))
    local right=ship:globalrot(_V(1,0,0))
    local up=ship:globalrot(_V(0,1,0))
    local nadir=vec.mul(vec.unit(ship:get_relativepos(earth)),-1)
    local x,y,z=dot(velocity,right),dot(velocity,up),dot(velocity,forward)
    local roll=math.atan2(dot(nadir,right),dot(nadir,up))
    return math.acos(clamp(z,-1,1)),roll,x,y,z
end
local function sample(marker,dv)
    local angle,roll=angles()
    local w=ship:get_angvel()
    local _,orbit=ship:get_elementsex(earth)
    local radius=oapi.get_size(earth)
    local distance=vec.length(vec.sub(oapi.get_globalpos(target),ship:get_globalpos()))
    local fuel=0
    for index=1,4 do fuel=fuel+ship:get_propellantmass(ship:get_propellanthandle(index)) end
    report:write(string.format("%.3f,%s,%.4f,%.4f,%.6f,%.6f,%.6f,%.7f,%.6f,%.4f,%.4f,%.3f,%d,%d\n",
        met(),marker,math.deg(angle),math.deg(roll),w.x,w.y,w.z,dv or 0,fuel,
        orbit.PeD-radius,orbit.ApD-radius,distance,ship:get_panelswitch("EMSDvDisplay"),ship:get_agcuplinkstatus()))
    report:flush()
end

proc.wait_simdt(1)
majorMode("Zero","Zero")
switch("CMUplinkSwitch",1)
sample("before_uplink")
oapi.simulatebufferedkey(OAPI_KEY.TAB)
proc.wait_simdt(0.5)
oapi.simulatebufferedkey(0x03)
-- Colossus uses erasable 01011 (bank 2, word 9) for the current program.
local sawP27=false
local limit=met()+170
while met()<limit do
    proc.wait_simdt(0.25)
    local program=ship:get_agcerasable(2,9)
    if not sawP27 and program==27 then
        sawP27=true
        sample("p27_started")
    elseif sawP27 and program==0 then
        sample("p27_returned_to_p00")
        break
    end
end
assert(sawP27 and ship:get_agcerasable(2,9)==0,"State vector uplink did not return to P00")
switch("CMUplinkSwitch",0)
proc.wait_simdt(1)
sample("uplink_complete")

while met()<11500 do
    if oapi.get_tacc()<10 and met()<11490 then oapi.set_tacc(10) end
    proc.wait_simdt(math.min(35,11500-met()))
end
oapi.set_tacc(1)
ship:set_rcsmode(1)
switch("SCContSwitch",0)
switch("AttRateSwitch",1)
switch("AttDeadbandSwitch",0)
switch("LimitCycleSwitch",0)
for _,name in ipairs({"RotPowerNormal1Switch","RotPowerNormal2Switch",
                      "RotPowerDirect1Switch","RotPowerDirect2Switch",
                      "BMAGRollSwitch","BMAGPitchSwitch","BMAGYawSwitch"}) do
    switch(name,2)
end
for _,name in ipairs({"ManualAttPitchSwitch","ManualAttYawSwitch","ManualAttRollSwitch"}) do
    switch(name,1)
end
local function drive(desired,actual,plus,minus)
    if desired-actual>0.004 then key(plus)
    elseif desired-actual< -0.004 then key(minus) end
end
local function orient()
    local angle,roll,x,y,z=angles()
    local w=ship:get_angvel()
    if z< -0.8 and math.abs(x)+math.abs(y)<0.15 then x=0.15 end
    local pitch=clamp(0.18*math.atan2(y,z),-0.033,0.033)
    local yaw=clamp(-0.18*math.atan2(x,z),-0.033,0.033)
    local bank=angle<0.35 and clamp(0.15*roll,-0.038,0.038) or 0
    drive(pitch,w.x,"NUMPAD2","NUMPAD8")
    drive(yaw,w.y,"NUMPAD1","NUMPAD3")
    drive(bank,w.z,"NUMPAD6","NUMPAD4")
end

-- Simulate the actual crew valve operations using the held spring-loaded controls.
for _,prefix in ipairs({"SMRCSHelium1","SMRCSHelium2","SMRCSProp1","SMRCSProp2"}) do
    for _,quad in ipairs({"A","B","C","D"}) do
        switch(prefix..quad.."Switch",2,true)
    end
    proc.wait_simdt(1)
    for _,quad in ipairs({"A","B","C","D"}) do
        switch(prefix..quad.."Switch",1)
    end
end
switch("AcRollA1Switch",1)
switch("AcRollA2Switch",1)
switch("AcRollC1Switch",1)
switch("AcRollC2Switch",1)
switch("BdRollB1Switch",2)
switch("BdRollB2Switch",2)
switch("BdRollD1Switch",0)
switch("BdRollD2Switch",0)
switch("PitchA3Switch",0)
switch("PitchA4Switch",2)
switch("PitchC3Switch",2)
switch("PitchC4Switch",0)
switch("YawB3Switch",2)
switch("YawB4Switch",0)
switch("YawD3Switch",0)
switch("YawD4Switch",2)

for _,name in ipairs({"ACRollMnACircuitBraker","ACRollMnBCircuitBraker","BDRollMnACircuitBraker",
                      "BDRollMnBCircuitBraker","PitchMnACircuitBraker","PitchMnBCircuitBraker",
                      "YawMnACircuitBraker","YawMnBCircuitBraker","SystemMnACircuitBraker",
                      "SystemMnBCircuitBraker","ContrAutoMnACircuitBraker","ContrAutoMnBCircuitBraker",
                      "ContrDirectMnA1CircuitBraker","ContrDirectMnB1CircuitBraker",
                      "ContrDirectMnA2CircuitBraker","ContrDirectMnB2CircuitBraker"}) do
    switch(name,1)
end
for _,quad in ipairs({"A","B","C","D"}) do
    switch("SMRCSHeater"..quad.."Switch",2)
end
sample("rcs_armed")

sample("orientation_start")
local nextLog=met()+10
local enteredP47=false
while met()<12000 do
    if not enteredP47 and met()>=11940 then
        majorMode("Four","Seven")
        switch("EMSFunctionSwitch",2)
        switch("EMSDvDisplay",-18)
        switch("EMSFunctionSwitch",1)
        switch("EMSModeSwitch",2)
        enteredP47=true
        assert(ship:get_agcerasable(2,9)==47, "CMC did not enter P47")
        sample("p47_armed")
    end
    orient()
    proc.wait_frames(1)
    if met()>=nextLog then
        sample("orient")
        nextLog=nextLog+10
    end
end
local angle=angles()
assert(angle<math.rad(5),string.format("Phasing attitude error %.2f degrees",math.deg(angle)))
switch("TransContrSwitch",1)
switch("THCRotary",1)
ship:set_rcsmode(2)
sample("before_burn")
local dv=0
local begin=met()
while met()-begin<8 and dv<0.54864 do
    key("NUMPAD9")
    proc.wait_frames(1)
    local force=ship:globalrot(ship:get_thrustvector())
    dv=dv-dot(force,vec.unit(ship:get_relativevel(earth)))*oapi.get_simstep()/ship:get_mass()
    sample("phasing_burn",dv)
end
for i=1,24 do
    proc.wait_frames(1)
    local force=ship:globalrot(ship:get_thrustvector())
    dv=dv-dot(force,vec.unit(ship:get_relativevel(earth)))*oapi.get_simstep()/ship:get_mass()
end
sample("after_burn",dv)
assert(dv>0.5 and dv<0.65,"Phasing impulse was outside tolerance")
ship:set_rcsmode(1)
local pro="DskySwitchProg"
switch(pro,1,true)
proc.wait_simdt(0.5)
switch(pro,0)
proc.wait_simdt(5)
majorMode("Zero","Zero")
switch("EMSFunctionSwitch",0)
switch("EMSModeSwitch",1)
switch("TransContrSwitch",0)
sample("phasing_complete",dv)
report:close()
