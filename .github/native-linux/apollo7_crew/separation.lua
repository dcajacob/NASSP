local ship = vessel.get_focusinterface()
local earth = ship:get_gravityref()
local radius = oapi.get_size(earth)
local report = assert(io.open("insertion-to-csm.csv", "w"))
report:write("met,marker,altitude,speed,mass,detached,tacc,periapsis,apoapsis,period\n")
local function sample(marker)
    local _, orbit = ship:get_elementsex(earth)
    local detached = oapi.get_objhandle("AS-205-S4BSTG")
    report:write(string.format("%.2f,%s,%.4f,%.5f,%.4f,%d,%.1f,%.4f,%.4f,%.4f\n",
        initialMET+oapi.get_simtime(), marker, ship:get_altitude(1),
        vec.length(ship:get_relativevel(earth)), ship:get_mass(), detached and 1 or 0,
        oapi.get_tacc(), orbit.PeD-radius, orbit.ApD-radius, orbit.T))
    report:flush()
    assert(orbit.PeD-radius > 150000, "Perigee has entered the upper atmosphere")
end

proc.wait_simdt(2)
sample("resume_coast")
local slowdown = 10085 - initialMET
local nextSample = oapi.get_simtime()+120
while oapi.get_simtime() < slowdown do
    if oapi.get_tacc() < 20 and slowdown-oapi.get_simtime() > 10 then
        sample("resume_warp")
        oapi.set_tacc(20)
    end
    proc.wait_simdt(math.min(15, slowdown-oapi.get_simtime()))
    if oapi.get_simtime() >= nextSample then
        sample("orbital_coast")
        nextSample = oapi.get_simtime()+120
    end
end
oapi.set_tacc(1)
proc.wait_simdt(15)
sample("before_sep")
ship:set_panelswitch("CsmLvSepSwitch", 1)
proc.wait_simdt(2.5)
sample("after_sep")
assert(oapi.get_objhandle("AS-205-S4BSTG"), "S-IVB did not separate")
ship:set_panelswitch("CsmLvSepSwitch", 0)
proc.wait_simdt(10)
sample("separate_orbits")
report:close()
