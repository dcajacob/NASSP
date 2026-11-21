"""Fly the final deorbit uplink, SPS burn, separation, entry and recovery on AS-205."""
import re
from pathlib import Path

from apollo7_checks import rows


CREW = Path(__file__).with_name("apollo7_crew")


def field(directory, name):
    save = (directory / "saved.scn").read_text(encoding="latin-1")
    return re.search(r"^  " + name + r" ([^\n]+)$", save, re.M)[1]


def fixture(chain, name):
    path = chain.runtime / "resources/Script/ProjectApollo" / ("apollo7-countdown-" + name + ".lua")
    return path.read_text()


def replace_once(script, pattern, replacement):
    script, count = re.subn(pattern, lambda _: replacement, script)
    assert count == 1, pattern
    return script


def burn(chain, preburn, pad):
    time_to_ignition = float(field(pad, "MCC_AP7MNV_GETI")) - float(field(preburn, "MISSNTIME"))
    assert time_to_ignition > 900, time_to_ignition
    duration = float(field(pad, "MCC_AP7MNV_burntime"))
    script = fixture(chain, "sps8-p40-burn")
    script = replace_once(script, r"local timeToIgnition = [\d.]+", f"local timeToIgnition = {time_to_ignition}")
    script = replace_once(script, r"local plannedDuration=[\d.]+", f"local plannedDuration={duration}")
    script = replace_once(script, "original_sps6_target", "retrofire_target")
    for switch, pad_field in (("SPSGimbalPitchThumbwheel", "pTrim"), ("SPSGimbalYawThumbwheel", "yTrim"),
                              ("EMSDvDisplay", "Vc")):
        value = round(float(field(pad, "MCC_AP7MNV_" + pad_field)) * 10)
        script = replace_once(script, rf'set\("{switch}",-?\d+\)', f'set("{switch}",{value})')
    flight = chain.leg(preburn, "sps8-burn", script, 75000, .0625,
                       "retrofire-burn.csv", "automatic_cutoff_confirmed")
    samples = rows(flight / "retrofire-burn.csv")
    final = samples[-1]
    assert float(final["periapsis"]) < 80000 < float(final["apoapsis"]), final
    assert float(samples[0]["sps_mass"]) - float(final["sps_mass"]) > 29.606 * max(1, duration-8)
    return flight


def verify_entry(p62, descent):
    gap = rows(p62 / "deorbit-to-entry.csv")
    by_event = {row["marker"]: row for row in gap}
    assert by_event["before_sm_sep"]["sm"] == "0" and by_event["after_sm_sep"]["sm"] == "1"
    assert by_event["cm_rcs_transfer_confirmed"]["program"] == "62"
    assert by_event["p63_entry_started"]["program"] == "63"
    samples = rows(descent / "deorbit-to-entry.csv")
    sequence = [row["marker"] for row in samples]
    events = ["entry_program_63", "entry_interface", "entry_program_64", "entry_program_67", "splashdown"]
    assert [sequence.index(event) for event in events] == sorted(sequence.index(event) for event in events)
    assert float(samples[0]["altitude"]) > 120000
    drogue = next(i for i, row in enumerate(samples) if row["drogue"] == "1")
    main = next(i for i, row in enumerate(samples) if row["main"] == "1")
    assert 0 < drogue < main < len(samples)-1
    final = samples[-1]
    assert final["marker"] == "splashdown" and final["program"] == "67"
    assert final["main"] == "1" and final["floatbag"] == "1"
    assert abs(float(final["altitude"])) < 2.5 and 0 <= float(final["airspeed"]) < 15, final
    assert field(descent, "STAGE") == "46"
    contact = float(field(descent, "SPLASHDOWN"))
    separation = float(field(descent, "CM_SM_SEPARATION_DONE"))
    assert abs(contact-float(final["met"])) < 5 and contact > separation > float(gap[0]["met"])


def enter(chain, previous, ignition):
    p61 = chain.leg(previous, "entry-p61", (CREW / "p61.lua").read_text(), 12000, .0625,
                    "entry-cmc.csv", "p62_waiting_for_service_module_sep")
    met = float(field(p61, "MISSNTIME"))
    script = f"local initialMET={met}\nlocal separationMET={ignition+385}\n" + (CREW / "p62.lua").read_text()
    p62 = chain.leg(p61, "entry-separation", script, 40000, .05, "deorbit-to-entry.csv", "p63_entry_started")
    met = float(field(p62, "MISSNTIME"))
    script = replace_once(fixture(chain, "entry-manual-attitude"), r"local initialMET = [\d.]+", f"local initialMET={met}")
    descent = chain.leg(p62, "entry-splashdown", script, 120000, .05, "deorbit-to-entry.csv", "splashdown")
    verify_entry(p62, descent)
    return descent


def fly(chain, previous):
    from apollo7_four import coast, prepare_p40
    from apollo7_middle import uplink_and_p30
    pad = coast(chain, previous, 8)
    confirmed = uplink_and_p30(chain, pad, 8)
    preburn = prepare_p40(chain, confirmed, pad, 8)
    deorbit = burn(chain, preburn, pad)
    return enter(chain, deorbit, float(field(pad, "MCC_AP7MNV_GETI")))
