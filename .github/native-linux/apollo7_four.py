"""Crew procedures for an unbroken Earth-orbit coast and SPS ignition setup."""
import json
from pathlib import Path
import re

CREW = Path(__file__).with_name("apollo7_crew")
SCHEDULE = {
    3: [(125190,36), (139000,37), (145000,"oxygen"), (160890,39), (181290,51),
        (194000,"heater_on"), (195200,"hydrogen"), (195500,"heater_off"), (205000,"oxygen"),
        (244300,54), (251000,"oxygen"), (259290,60)],
    4: [(279900,"charge_b"), (291300,"stop_charge"), (295200,"oxygen"), (322250,64), (339360,65), (357670,72),
        (381600,"oxygen"), (423080,75)],
    5: [(445000,83), (468000,"oxygen"), (503160,87), (509400,"oxygen"),
        (517580,89), (524780,102), (530480,105), (540300,"heater_on"),
        (541500,"hydrogen"), (541800,"heater_off"), (554400,"oxygen"), (580290,107)],
    6: [(609080,120), (669000,"heater_on"), (670200,"hydrogen"), (670500,"heater_off"),
        (670600,"oxygen"), (689790,124), (697290,131), (702000,"oxygen"), (728190,132), (739590,134)],
    7: [(760200,"heater_on"), (761400,"hydrogen"), (761700,"heater_off"),
        (766890,138), (783390,150), (788400,"oxygen"), (810600,"heater_on"),
        (811800,"hydrogen"), (812100,"heater_off"), (827400,"oxygen"), (840690,153)],
    8: [(864990,160), (865800,"charge_b"), (877200,"stop_charge"), (884400,"heater_on"), (885600,"hydrogen"), (885900,"heater_off"),
        (900000,"check_charge_a"), (911400,"stop_charge"), (914400,"heater_on"), (915600,"hydrogen"), (915900,"heater_off"), (918690,163)],
}
PURPOSE = {3: "SPS-3", 4: "SPS-4, MINIMUM IMPULSE", 5: "SPS-5 / PUGS",
           6: "SPS-6, MINIMUM IMPULSE", 7: "SPS-7", 8: "164-1A RETROFIRE"}


def scenario_field(directory, name):
    text = (Path(directory) / "saved.scn").read_text()
    return re.search(r"^  " + name + r" (.+)$", text, re.M)[1]


def coast(chain, previous_dir, number):
    schedule = SCHEDULE[number]
    rows = [f"{{{get},{action}}}" if isinstance(action, int)
            else f"{{{get},nil,{json.dumps(action)}}}" for get, action in schedule]
    args = (f"local initial_get={float(scenario_field(previous_dir, 'MISSNTIME'))}\n"
            f"local schedule={{{','.join(rows)}}}\nlocal burn_state={schedule[-1][1]}\n"
            f"local burn_purpose={json.dumps(PURPOSE[number])}\n")
    return chain.leg(previous_dir, f"sps{number}-coast", args + (CREW / "coast.lua").read_text(),
                     120000, .125, "coast.csv", "maneuver_pad_ready")


def alignment_script(runtime, coast_seconds):
    table = runtime / "resources/Config/ProjectApollo/RTCC/Star Table.txt"
    # RTCC writes the inertial star catalog in a right-handed frame. Orbiter
    # uses ecliptic north as its second axis.
    stars = []
    for line in table.read_text().splitlines()[:37]:
        x, y, z = map(float, line.split())
        stars.append(f"vec.unit(_V({x},{z},{y}))")
    if len(stars) != 37:
        raise ValueError("Incomplete Apollo navigation star catalog")
    return (f"local coast_seconds={coast_seconds}\nlocal stars={{{','.join(stars)}}}\n"
            + (CREW / "align.lua").read_text())


def prepare_p40(chain, previous_dir, pad_dir, number, *, realign=True):
    def pad(field):
        return float(scenario_field(pad_dir, "MCC_AP7MNV_" + field))
    present = float(scenario_field(previous_dir, "MISSNTIME"))
    ignition = pad("GETI")
    if realign:
        alignment = alignment_script(chain.runtime, max(0, ignition - present - 2120))
        if number == 3 and "  OPTICSCOVERED 1\n" in (previous_dir/"saved.scn").read_text():
            alignment = "local prepare_launch_optics=true\n" + alignment
        previous_dir = chain.leg(previous_dir, f"sps{number}-alignment", alignment, 300000, .015625,
                                 "alignment.csv", "platform_reference_ready")
        present = float(scenario_field(previous_dir, "MISSNTIME"))
    if ignition - present < 1000:
        raise ValueError(f"Insufficient time for SPS-{number} R60 slew")
    config = "11102" if number in (1, 2, 3, 7, 8, "ncc2") else "10102"
    scenario = (previous_dir / "saved.scn").read_text()
    def quad_mass(quad):
        block = re.search(rf"^SMRCSPROPELLANT_{quad}_BEGIN\n  PROPELLANTMASS (\S+)", scenario, re.M)
        return float(block[1])
    # Each pair can control roll. Preserve the lower-reserve pair for the axes
    # only its jets can control (A/C pitch, B/D yaw).
    bd_roll = min(quad_mass("A"), quad_mass("C")) < min(quad_mass("B"), quad_mass("D"))
    roll_word = "01111" if bd_roll else "11111"
    args = (f'local roll_word="{roll_word}"\nlocal dap_config="{config}"\nlocal csm_weight={round(pad("Weight"))}\n'
            f'local pitch_trim={round(100 * pad("pTrim"))}\n'
            f'local yaw_trim={round(100 * pad("yTrim"))}\n'
            f'local waitUntil={ignition - present - 1350}\n')
    return chain.leg(previous_dir, f"sps{number}-prepare-p40",
                     args + (CREW / "prepare-p40.lua").read_text(), 110000, .125,
                     "prepare-p40.csv", "ready_for_slew")


def burn_sps4(chain, ready, pad):
    from apollo7_middle import substitute
    pinned = chain.runtime / "resources/Script/ProjectApollo/apollo7-countdown-sps4-p40-burn.lua"
    source = pinned.read_text()
    # Keep R60 and the subsequent attitude hold at the normal guidance sample
    # interval. Under warp, a CMC jet pulse can last many control cycles.
    source = re.sub(r"oapi\.set_tacc\([^)]*\)", "oapi.set_tacc(1)", source)

    def target(name):
        return float(scenario_field(pad, "MCC_AP7MNV_" + name))

    delay = target("GETI") - float(scenario_field(ready, "MISSNTIME"))
    source = substitute(source, r"^local timeToIgnition = .*", f"local timeToIgnition = {delay}")
    source = substitute(source, r'^set\("EMSDvDisplay",\d+\)',
                        f'set("EMSDvDisplay",{round(10 * target("Vc"))})')
    # SPS-4 uses the B/D pair only. Main A powers B4 and D3, while main B
    # powers A4 and C3. Record the acceleration while those two valves are held.
    source = substitute(source, r'^at\(-10,"ullage_complete"\)', """
local initialOrbit=select(2,ship:get_elementsex(ship:get_gravityref()))
local initialA=(initialOrbit.PeD+initialOrbit.ApD)/2
local previousTime=oapi.get_simtime()
local impulse=0
while oapi.get_simtime()<timeToIgnition-10 do
    proc.wait_frames(1)
    local now=oapi.get_simtime()
    impulse=impulse+ship:get_thrustvector().z*(now-previousTime)/ship:get_mass()
    previousTime=now
end
reportState("ullage_complete")
assert(impulse>.55 and impulse<1.9,"Missing B/D ullage impulse")
""")
    # The original R60, V99, SPS consumption, automatic cutoff and slosh
    # observations run before independently checking this mission's live PAD.
    check = f"""
local earth=ship:get_gravityref()
local _,orbit=ship:get_elementsex(earth)
local radius=oapi.get_size(earth)
assert(math.abs(orbit.PeD-radius-{target("HP") * 1852})<15000, "SPS-4 missed PAD perigee")
assert(math.abs(orbit.ApD-radius-{target("HA") * 1852})<15000, "SPS-4 missed PAD apogee")
local finalA=(orbit.PeD+orbit.ApD)/2
-- For a short posigrade maneuver, differentiate orbital energy -mu/(2a).
local speed=vec.length(ship:get_relativevel(earth))
local mu=3.986004418e14
local achieved=mu*(1/initialA-1/finalA)/(2*speed)
local expected={float(scenario_field(pad, "MCC_AP7MNV_dV").split()[0])*0.3048}
assert(achieved>.5*expected and achieved<1.5*expected,"SPS-4 orbital energy change disagrees with PAD")
local receipt=assert(io.open("burn.csv","w"))
receipt:write("ullage_delta_v_m_s,achieved_delta_v_m_s,target_delta_v_m_s,sps_kg\\n",
              string.format("%.5f,%.5f,%.5f,%.5f\\n",impulse,achieved,expected,used))
receipt:close()
reportState("linked_burn_verified")
"""
    source = substitute(source, r"^report:close\(\)", check + "report:close()")
    return chain.leg(ready, "sps4-burn", source, 80000, .0625,
                     "sps4-p40.csv", "linked_burn_verified")


def fly(chain, previous_dir):
    from apollo7_middle import uplink_and_p30
    pad = coast(chain, previous_dir, 4)
    checked = uplink_and_p30(chain, pad, 4)
    ready = prepare_p40(chain, checked, pad, 4)
    return burn_sps4(chain, ready, pad)
