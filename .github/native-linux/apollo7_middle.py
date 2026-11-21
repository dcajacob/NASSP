"""Fly the next crew procedure using the MCC PAD on this save chain."""

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
    return "local loads=" + table(loads) + "\n" + (CREW / "uplink.lua").read_text()


def p30(chain, previous_dir, pad_dir, number):
    raw = saved(pad_dir)
    tig = float(field(raw, "MCC_AP7MNV_GETI"))
    dv = list(map(float, field(raw, "MCC_AP7MNV_dV").split()))
    if len(dv) != 3:
        raise ValueError("Expected a three-component LVLH target")
    lua = f"local tig,deltaV={tig},{table(dv)}\n" + (CREW / "p30.lua").read_text()
    return chain.leg(previous_dir, f"sps{number}-p30", lua, 5000, .125,
                     "p30.csv", "p30_pad_verified")


def uplink_and_p30(chain, pad_dir, number):
    directory = chain.leg(pad_dir, f"sps{number}-uplink", uplink_script(saved(pad_dir), number),
                          14000, .125, "uplink.csv", "target_uplink_verified")
    return p30(chain, directory, pad_dir, number)


BURNS = {
    5: ("manual-tvc-burn", "sps5-manual-tvc.csv", "manual_cutoff_confirmed"),
    6: ("p40-burn", "sps6-p40.csv", "automatic_cutoff_confirmed"),
    7: ("scs-burn", "sps7-scs.csv", "ems_cutoff_confirmed"),
}


def substitute(source, pattern, value):
    updated, changes = re.subn(pattern, lambda m: value, source, flags=re.MULTILINE)
    if changes != 1:
        raise ValueError(f"Expected one matching line in pinned crew script for {pattern}")
    return updated


def burn_script(runtime, preburn_raw, pad_raw, number):
    template, _, _ = BURNS[number]
    script = runtime / f"resources/Script/ProjectApollo/apollo7-countdown-sps{number}-{template}.lua"
    source = script.read_text()
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

    # CMC translation via the normal THC uses the B/D-only DAP for SPS-5/6.
    # SCS uses all four jets for SPS-7. Leave manual ignition's momentary
    # direct ullage interlock alone.
    if number == 7:
        start = source.index('ship:set_panelswitch("DirectUllageButton",1,true)')
        end = source.index('at(-5,"cmc_monitoring")', start)
    else:
        start = source.index('set("DirectUllMnACircuitBraker",1)')
        end = source.index("local initialMass=", start)
    ullage = "local ullageEnd=timeToIgnition-" + ("15" if number == 7 else "10") + "\n"
    source = source[:start] + ullage + (CREW / "ullage.lua").read_text() + source[end:]
    duration = pad("burntime")
    if number == 7:
        source = substitute(source, r"^local plannedDuration=.*", f"local plannedDuration={duration}")
        source = source.replace('set("SCContSwitch",0)', 'set("AttRateSwitch",0)\nset("SCContSwitch",0)')
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
    return source


def fly_stage(chain, previous_dir, number):
    from apollo7_four import coast, prepare_p40
    pad = coast(chain, previous_dir, number)
    raw = saved(pad)
    if number == 5:
        propellant = re.search(r"SPSPROPELLANT_BEGIN\n.*?^  PROPELLANTMASS ([\d.]+)", raw, re.S | re.M)
        remaining = float(propellant[1]) - 29.606 * float(field(raw, "MCC_AP7MNV_burntime"))
        if remaining < 700:
            raise ValueError(f"SPS-5 target leaves only {remaining:.1f} kg for later burns")
    p00 = uplink_and_p30(chain, pad, number)
    ready = prepare_p40(chain, p00, pad, number)
    _, csv_name, marker = BURNS[number]
    return chain.leg(ready, f"sps{number}-burn", burn_script(chain.runtime, saved(ready), raw, number),
                     75000, .0625, csv_name, marker)


def fly(chain, previous_dir):
    for number in BURNS:
        previous_dir = fly_stage(chain, previous_dir, number)
    return previous_dir
