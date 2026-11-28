"""Fly the next crew procedure using the MCC PAD on this save chain."""

import math
import re
from pathlib import Path

CREW = Path(__file__).with_name("apollo7_crew")


def saved(directory):
    return (directory / "saved.scn").read_text()


def field(raw, name):
    match = re.search(r"^  " + re.escape(name) + r" (.+)$", raw, re.MULTILINE)
    if not match:
        raise ValueError(f"Missing {name} in the linked save")
    return match[1]


def words(packet, prefix, length):
    pattern = re.escape(prefix) + rf"((?:[0-7]{{1,5}}E){{{length}}})"
    match = re.fullmatch(pattern, packet)
    if not match:
        raise ValueError(f"Unexpected MCC packet for {prefix}")
    return [int(word, 8) for word in match[1][:-1].split("E")]


def table(numbers):
    return "{" + ",".join(map(str, numbers)) + "}"


def uplink_script(raw, number):
    specs = [
        ("csm_state_vector", "V71E21E1501E1E", 14, 3, 0x6C),
        ("second_state_vector", "V71E21E1501E77776E", 14, 3, 0x96),
    ]
    if number == 8:
        specs.extend([
            ("retrofire_target", "V71E16E3400E", 12, 7, 0),
            ("entry_reference", "V71E24E306E", 18, 0, 0o306),
        ])
    else:
        specs.append(("external_delta_v", "V71E12E3404E", 8, 7, 4))
    packets = field(raw, "MCC_upString").split("V33E")
    if packets.pop() or len(packets) != len(specs):
        raise ValueError(f"Incomplete SPS-{number} MCC packet sequence")
    loads = []
    for packet, (name, prefix, count, bank, address) in zip(packets, specs):
        values = table(words(packet, prefix, count))
        loads.append(f'{{name="{name}", bank={bank}, address={address}, words={values}}}')
    final_ncc1 = number == 1 and field(raw, "MCC_AP7MNV_purpose") == "NCC-1"
    # The CMC advances its rectification epoch between coast integrations.
    # Start the transfer after that transition, leaving time for explicit
    # word-by-word readback of the entire multi-packet uplink.
    settle = "proc.wait_simdt(155)\n" if final_ncc1 else ""
    if number == 3:
        window = min(1800, float(field(raw,"MCC_AP7MNV_GETI")) - float(field(raw,"MISSNTIME")) - 1900)
        if window < 100:
            raise ValueError("Insufficient time to synchronize the navigation uplink")
        settle = f"local navigation_window={window}\n"
    wait = number in (2, 3, 7, 8, "ncc2") or final_ncc1
    return (settle + f"local waitForNavigation={str(wait).lower()}\nlocal loads="
            + table(loads) + "\n" + (CREW / "uplink.lua").read_text())


def p30(chain, previous_dir, pad_dir, number, *, manual_entry=False):
    raw = saved(pad_dir)
    tig = float(field(raw, "MCC_AP7MNV_GETI"))
    dv = list(map(float, field(raw, "MCC_AP7MNV_dV").split()))
    if len(dv) != 3:
        raise ValueError("Expected a three-component LVLH target")
    lua = (f"local tig,deltaV={tig},{table(dv)}\nlocal manual_entry={str(manual_entry).lower()}\n"
           + (CREW / "p30.lua").read_text())
    return chain.leg(previous_dir, f"sps{number}-p30", lua, 5000, .125,
                     "p30.csv", "p30_pad_verified")


def uplink_and_p30(chain, pad_dir, number):
    directory = chain.leg(pad_dir, f"sps{number}-uplink", uplink_script(saved(pad_dir), number),
                          14000, .125, "uplink.csv", "target_uplink_verified")
    return p30(chain, directory, pad_dir, number)


BURNS = {
    5: ("manual-tvc-burn", "sps5-manual-tvc.csv"),
    6: ("p40-burn", "sps6-p40.csv"),
    7: ("scs-burn", "sps7-scs.csv"),
}


def substitute(source, pattern, value):
    updated, changes = re.subn(pattern, lambda m: value, source, flags=re.MULTILINE)
    if changes != 1:
        raise ValueError(f"Expected one matching line in pinned crew script for {pattern}")
    return updated


def burn_script(runtime, preburn_raw, pad_raw, number):
    rendezvous = number in (1, 2, "ncc2")
    procedure = 6 if rendezvous else number
    template, _ = BURNS[procedure]
    script = runtime / f"resources/Script/ProjectApollo/apollo7-countdown-sps{procedure}-{template}.lua"
    source = script.read_text()
    # The CMC DAP controls individual jet pulses. Keep its closed-loop slew
    # and attitude hold at the burn step, including the wait for the gimbal tests.
    source = source.replace("oapi.set_tacc(remaining>100 and 2.5 or 1)", "oapi.set_tacc(1)")
    source = source.replace("oapi.set_tacc(8)", "oapi.set_tacc(1)").replace("oapi.set_tacc(4)", "oapi.set_tacc(1)")
    def pad(name):
        return float(field(pad_raw, "MCC_AP7MNV_" + name))

    delay = pad("GETI") - float(field(preburn_raw, "MISSNTIME"))
    if delay <= 385:
        raise ValueError(f"Too late for SPS-{number} R60 and gimbal checks")
    source = substitute(source, r"^local timeToIgnition = .*", f"local timeToIgnition = {delay}")
    for switch, value in (("EMSDvDisplay", pad("Vc")),
                          ("SPSGimbalPitchThumbwheel", pad("pTrim")),
                          ("SPSGimbalYawThumbwheel", pad("yTrim"))):
        source = substitute(source, r'^set\("' + switch + r'",-?\d+\)',
                            f'set("{switch}",{round(value * 10)})')

    # The two-jet crew procedure uses the B/D pair with CMC pitch control.
    # SCS uses all four jets for SPS-7. Leave manual ignition's momentary
    # direct ullage interlock alone.
    if number == 7:
        start = source.index('ship:set_panelswitch("DirectUllageButton",1,true)')
        end = source.index('at(-5,"cmc_monitoring")', start)
    else:
        start = source.index('set("DirectUllMnACircuitBraker",1)')
        end = source.index("local initialMass=", start)
    ullage = "local ullageEnd=timeToIgnition-" + ("15" if number == 7 or rendezvous else "10") + "\n"
    ullage += "local twoJet=" + ("false" if number == 7 or rendezvous else "true") + "\n"
    ullage += "local minimumImpulse=" + ("true" if number == 6 else "false") + "\n"
    source = source[:start] + ullage + (CREW / "ullage.lua").read_text() + source[end:]
    duration = pad("burntime")
    if rendezvous:
        # Same CMC P40 as SPS-6, with four-jet ullage and live duration.
        # The independent vector and apsis checks below qualify the cutoff.
        source = substitute(source, r'^assert\(used>4 and used<65,.*$',
                            'assert(used>0,"Rendezvous SPS did not consume propellant")')
        source = substitute(source, r'^for i=1,60 do$', f'for i=1,{60 + math.ceil(duration)} do')
    if number == 7:
        source = substitute(source, r"^local plannedDuration=.*", f"local plannedDuration={duration}")
        source = source.replace('set("SCContSwitch",0)', 'set("AttRateSwitch",0)\nset("SCContSwitch",0)')
        source = substitute(source, r"^local previousMode=", (CREW / "sps7-steer.lua").read_text()
                            + "\nlocal previousMode=")
        source = substitute(source, r'^at\(-5,"cmc_monitoring"\)', '''set("SCContSwitch",0)
ship:set_rcsmode(1)
for _,axis in ipairs({"Pitch","Yaw","Roll"}) do set("ManualAtt"..axis.."Switch",2) end
steerUntil(timeToIgnition-5)
at(-5,"cmc_monitoring")''')
        source = substitute(source, r'^at\(0,"manual_ignition"\)', 'steerUntil(timeToIgnition)\nat(0,"manual_ignition")')
        source = substitute(source, r'^set\("AttRateSwitch",1\)', '''set("AttRateSwitch",1)
set("SCSTvcPitchSwitch",1)
set("SCSTvcYawSwitch",1)
set("THCRotary",2)''')
        source = substitute(source, r'    proc.wait_simdt\(\.125\)', '    steer()\n    proc.wait_frames(2)')
    if number == 5:
        takeover = duration - 30  # RTCC prints this in the PUGS PAD remarks.
        if not 0 < takeover < duration:
            raise ValueError(f"Invalid PUGS manual takeover {takeover}")
        source = substitute(source, r"while oapi.get_simtime\(\)<timeToIgnition\+[\d.]+ do",
                            f"while oapi.get_simtime()<timeToIgnition+{takeover} do")
        source = substitute(source, r"initialMass-ship:get_propellantmass\(sps\)>[\d.]+",
                            f"initialMass-ship:get_propellantmass(sps)>{21 * takeover}")
        source = substitute(source, r'timeToIgnition\+96,"EMS', f'timeToIgnition+{duration + 25},"EMS')
        source = substitute(source, r"initialMass-shutoffMass>[\d.]+ and initialMass-shutoffMass<[\d.]+",
                            f"initialMass-shutoffMass>{29.606 * (duration-20)} and "
                            f"initialMass-shutoffMass<{29.606 * (duration+20)}")
    dv = list(map(float, field(pad_raw, "MCC_AP7MNV_dV").split()))
    if len(dv) != 3:
        raise ValueError("Missing target delta-v")
    header = (f"local padPerigee,padApogee={pad('HP') * 1852},{pad('HA') * 1852}\n"
              f"local padMagnitude={math.hypot(*dv) * .3048}\n")
    measure = ("local ignitionMass=ship:get_mass()\n"
               "local ignitionPropellant=ship:get_propellantmass(sps)\n")
    source = substitute(source, r'^reportState\("ullage_complete"\)', measure + 'reportState("ullage_complete")')
    # Track all thrust, including ullage, in the PAD axes at the time of ignition.
    target = "local padLVLH=" + table([.3048*x for x in dv]) + "\n"
    target += (CREW / "burn-integral.lua").read_text()
    source = substitute(source, r'^at\(-30,"ullage"\)', 'at(-30,"ullage")\n' + target)
    if number == 5:
        # During manual takeover steer the RHC against the inertial velocity
        # still to go. Holding the body axis at takeover loses the RTCC pitch.
        source = substitute(source, r"^local reference=ship:globalrot\(_V\(0,0,1\)\)", "local reference=remainingDirection()")
        source = substitute(source, r"^local function steer\(\)", "local function steer()\n"
                            "    if display()>1800 then reference=remainingDirection() end")
    source = substitute(source, r"^report:close\(\)", (CREW / "burn-result.lua").read_text() + "report:close()")
    return header + source


def fly_stage(chain, previous_dir, number):
    from apollo7_four import coast, prepare_p40
    pad = coast(chain, previous_dir, number)
    raw = saved(pad)
    if number == 5:
        propellant = re.search(r"SPSPROPELLANT_BEGIN\n.*?^  PROPELLANTMASS ([\d.]+)", raw, re.S | re.M)
        remaining = float(propellant[1]) - 29.606 * float(field(raw, "MCC_AP7MNV_burntime"))
        if remaining < 700:
            pad = chain.leg(pad, "sps5-retarget", (CREW / "retarget.lua").read_text(),
                            4000, .125, "retarget.csv", "recovery_reserve_verified")
            raw = saved(pad)
    p00 = uplink_and_p30(chain, pad, number)
    ready = prepare_p40(chain, p00, pad, number)
    _, csv_name = BURNS[number]
    return chain.leg(ready, f"sps{number}-burn", burn_script(chain.runtime, saved(ready), raw, number),
                     75000, .0625, csv_name, "linked_burn_verified")


def fly(chain, previous_dir):
    for number in BURNS:
        previous_dir = fly_stage(chain, previous_dir, number)
    return previous_dir
