-- The SPS exhaust speed (m/s) is defined by NASSP's SPS_ISP. Use the measured
-- propellant debit and live vessel mass for the delivered velocity estimate.
local propellantUsed=ignitionPropellant-ship:get_propellantmass(sps)
local delivered=3080*math.log(ignitionMass/(ignitionMass-propellantUsed))+impulse
local earth=ship:get_gravityref()
local _,elements=ship:get_elementsex(earth)
local pe=elements.PeD-oapi.get_size(earth)
local ap=elements.ApD-oapi.get_size(earth)
local result=assert(io.open("burn-result.csv","w"))
result:write("pad_perigee_m,perigee_m,pad_apogee_m,apogee_m,pad_delta_v_m_s,delivered_m_s,ullage_m_s,sps_kg\n")
result:write(string.format("%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%.3f\n",
    padPerigee,pe,padApogee,ap,padMagnitude,delivered,impulse,propellantUsed))
result:close()
assert(math.abs(pe-padPerigee)<15000,"Burn missed the PAD perigee")
assert(math.abs(ap-padApogee)<15000,"Burn missed the PAD apogee")
assert(math.abs(delivered-padMagnitude)<math.max(2,.03*padMagnitude),"Burn missed the target delta-v")
reportState("linked_burn_verified")
