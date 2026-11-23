-- The CMC entry DAP steers the lift vector by commanding bank during P63-P67.
assert(ship:get_agcerasable(2,9)==63 and present("SM")==1)
set("SCContSwitch",1)
set("CMCModeSwitch",2)
local trace=assert(io.open("entry-navigation.csv","w"))
trace:write("met,program,latitude_deg,longitude_deg,altitude_m,air_speed_m_s,cmc_radius_m,cmc_inertial_speed_m_s\n")
local function fraction(address)
    local function word(addr)
        local value=ship:get_agcerasable(math.floor(addr/256),addr%256)
        return value>=16384 and value-32767 or value
    end
    return word(address)/16384+word(address+1)/268435456
end
local function magnitude(start,scale)
    local x,y,z=fraction(start),fraction(start+2),fraction(start+4)
    return scale*math.sqrt(x*x+y*y+z*z)
end
local phases={}
local interface=false
local armed=false
local nextLog=0
while oapi.get_simtime()<3000 do
    local now=oapi.get_simtime()
    local alt=ship:get_altitude(1)
    local speed=ship:get_airspeed()
    local program=ship:get_agcerasable(2,9)
    if not phases[program] then
        sample("entry_program_"..program)
        phases[program]=true
    end
    if not interface and alt<=120000 then
        sample("entry_interface")
        interface=true
    end
    if not armed and alt<12200 then
        set("ELSLogicSwitch",1)
        set("ELSAutoSwitch",1)
        armed=true
        sample("els_armed")
    end
    if now>=nextLog then
        local pos=ship:get_equpos()
        trace:write(string.format("%.3f,%d,%.6f,%.6f,%.1f,%.2f,%.1f,%.2f\n",initialMET+now,program,
            math.deg(pos.lat),math.deg(pos.lng),alt,speed,magnitude(tonumber("1170",8),2^29),
            magnitude(tonumber("1176",8),100*2^7)))
        trace:flush()
        sample("descent")
        nextLog=now+3
    end
    if alt<2.5 and speed<15 and present("MAINCHUTE")==1 then
        assert(phases[67] and present("DROGUECHUTE")==1)
        sample("splashdown")
        trace:close()
        report:close()
        oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
        proc.wait_frames(6)
        oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
        return
    end
    if present("MAINCHUTE")==1 and alt<2200 and alt>75 then oapi.set_tacc(3) else oapi.set_tacc(1) end
    proc.wait_frames(1)
end
error("CMC entry did not reach splashdown")
