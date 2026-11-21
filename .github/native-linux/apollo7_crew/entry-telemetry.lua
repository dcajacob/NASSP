local ship = vessel.get_focusinterface()
local earth = ship:get_gravityref()
local report = assert(io.open("deorbit-to-entry.csv", "w"))
report:write("met,marker,altitude,airspeed,heatshield_angle,body_rate,tacc,sm,apex,drogue,main,floatbag,program,verb,noun\n")
local function present(name)
    return oapi.get_objhandle("AS-205-"..name) and 1 or 0
end
local function sample(marker)
    local rot = ship:get_rotationmatrix()
    local v = vec.unit(ship:get_relativevel(earth))
    local dot = -v.x*rot.m13-v.y*rot.m23-v.z*rot.m33
    local angle = math.deg(math.acos(math.max(-1,math.min(1,dot))))
    report:write(string.format("%.2f,%s,%.4f,%.4f,%.3f,%.5f,%.1f,%d,%d,%d,%d,%d,%d,%d,%d\n",
        initialMET+oapi.get_simtime(), marker, ship:get_altitude(1), ship:get_airspeed(),
        angle, vec.length(ship:get_angvel()), oapi.get_tacc(),
        present("SM"),present("APEX"),present("DROGUECHUTE"),present("MAINCHUTE"),present("FLOATBAG"),ship:get_agcerasable(2,9),
        ship:get_agcerasable(2,1),ship:get_agcerasable(2,2)))
    report:flush()
end
local function set(name, value, hold)
    ship:set_panelswitch(name, value, hold)
    assert(ship:get_panelswitch(name)==value,"Switch did not move: "..name)
end
