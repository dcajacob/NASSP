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
    # A two-axis SM slew can run until its time limit and spend the last of
    # the B/D propellant. Use powered CM attitude jets for the R60 maneuver,
    # just as the original procedure does for final trim. Keep SM fuel for settling.
    start = script.index('oapi.set_tacc(4)\nat(-680,')
    end = script.index('at(-68,"late_attitude_check")', start)
    script = script[:start] + (CREW / "deorbit-ullage.lua").read_text() + script[end:]
    script = replace_once(script, r'at\(-30,"ullage"\)', 'at(depleted and -8 or -25,"ullage")')
    start = script.index('set("DirectUllMnACircuitBraker",1)', script.index('at(depleted and -8'))
    end = script.index("local initialMass=", start)
    normal = ('set("SCContSwitch",1)\nset("CMCModeSwitch",2)\nset("ManualAttPitchSwitch",2)\n'
              'local twoJet=true\nlocal minimumImpulse=false\n' + (CREW / "ullage.lua").read_text()
              + 'set("ManualAttPitchSwitch",1)\n')
    finish = """if depleted then
    directPulse(2)
    local dot=vec.dotp(targetZ,ship:globalrot(_V(0,0,1)))
    local pointing=math.deg(math.acos(math.max(-1,math.min(1,dot))))
    local log=assert(io.open("ullage.csv","w"))
    log:write("axial_delta_v_m_s,pointing_error_deg\\n",string.format("%.6f,%.6f\\n",impulse,pointing))
    log:close()
    assert(impulse>.4 and impulse<3,"Deorbit settling impulse missed its target")
    assert(pointing<3,"R60 pointing was not held to ignition")
    reportState("ullage_complete")
    set("SCContSwitch",1)
    set("CMCModeSwitch",2)
else
    local ullageEnd=timeToIgnition-10
"""
    script = script[:start] + finish + normal + "end\n" + script[end:]
    # Restoring the SM jets after trimming with the CM jets requires power
    # to both transfer motors. Either relay left on CM inhibits translation.
    script = replace_once(script, r'at\(-38,"arm_sps"\)', """at(-38,"arm_sps")
for _,name in ipairs({"BatCPWRCircuitBraker","BatCtoBatBusACircuitBraker","BatCtoBatBusBCircuitBraker",
                     "RCSLogicMnACircuitBraker","RCSLogicMnBCircuitBraker"}) do set(name,1) end
set("MainBusTieBatAcSwitch",2)
set("MainBusTieBatBcSwitch",2)""")
    flight = chain.leg(preburn, "sps8-burn", script, 75000, .0625,
                       "retrofire-burn.csv", "automatic_cutoff_confirmed")
    verify_burn(flight, pad)
    return flight


def verify_burn(flight, pad):
    samples = rows(flight / "retrofire-burn.csv")
    final = samples[-1]
    assert float(final["periapsis"]) < 80000 < float(final["apoapsis"]), final
    assert final["marker"] == "automatic_cutoff_confirmed" and samples[0]["marker"] == "retrofire_target"
    authorized = [row for row in samples if row["marker"] == "v99_authorized"]
    assert len(authorized) == 1 and -6 <= float(authorized[0]["relative_to_tig"]) < 1
    # Full-thrust propellant usage is approximately 29.6 kg/s, with transients at start/stop.
    duration = float(field(pad, "MCC_AP7MNV_burntime"))
    used = float(samples[0]["sps_mass"]) - float(final["sps_mass"])
    assert .8 * duration * 29.606 < used < 1.2 * duration * 29.606, used


def verify_entry(p62, recovery):
    descent = recovery.parent / "entry-splashdown"
    gap = rows(p62 / "deorbit-to-entry.csv")
    by_event = {row["marker"]: row for row in gap}
    assert by_event["before_sm_sep"]["sm"] == "0" and by_event["after_sm_sep"]["sm"] == "1"
    assert by_event["cm_rcs_transfer_confirmed"]["program"] == "62"
    preparation = rows((p62.parent / "entry-attitude") / "deorbit-to-entry.csv")
    assert preparation[0]["marker"] == "cm_separation_reloaded" and preparation[0]["sm"] == "1"
    assert preparation[-1]["marker"] == "p63_entry_started" and preparation[-1]["program"] == "63"
    samples = rows(descent / "deorbit-to-entry.csv")
    sequence = [row["marker"] for row in samples]
    events = ["entry_program_63", "entry_interface", "entry_program_64", "entry_program_67", "splashdown"]
    assert [sequence.index(event) for event in events] == sorted(sequence.index(event) for event in events)
    assert float(samples[0]["altitude"]) > 120000
    interface = samples[sequence.index("entry_interface")]
    assert 119000 < float(interface["altitude"]) <= 120000 and float(interface["airspeed"]) > 7000
    # The manual entry crew commands 19 degrees incidence to the heat shield.
    assert 5 < float(interface["heatshield_angle"]) < 35 and float(interface["body_rate"]) < .05
    drogue = next(i for i, row in enumerate(samples) if row["drogue"] == "1")
    main = next(i for i, row in enumerate(samples) if row["main"] == "1")
    assert 0 < drogue < main < len(samples)-1
    final = samples[-1]
    assert final["marker"] == "splashdown" and final["program"] == "67"
    assert final["main"] == "1" and final["floatbag"] == "1"
    assert abs(float(final["altitude"])) < 2.5 and 0 <= float(final["airspeed"]) < 15, final
    settled = rows(recovery / "recovery.csv")
    assert [row["event"] for row in settled] == ["water_contact", "mains_released", "settled_recovery"]
    assert all(row["ground_contact"] == "true" for row in settled)
    assert [row["main_attached"] for row in settled] == ["true", "false", "false"]
    assert float(settled[-1]["elapsed"]) - float(settled[1]["elapsed"]) >= 60
    assert float(settled[-1]["airspeed"]) < 1 and abs(float(settled[-1]["altitude"])) < 3
    assert field(recovery, "STATUS") == "Landed Earth" and field(recovery, "STAGE") == "47"
    lng, lat = map(float, field(recovery, "POS").split())
    assert abs(lng-float(settled[-1]["longitude"])) < .001 and abs(lat-float(settled[-1]["latitude"])) < .001
    assert field(descent, "STAGE") == "46"
    assert abs(float(field(descent, "SPLASHDOWN")) - float(field(recovery, "SPLASHDOWN"))) < .1
    contact = float(field(descent, "SPLASHDOWN"))
    separation = float(field(descent, "CM_SM_SEPARATION_DONE"))
    assert abs(contact-float(final["met"])) < 5 and contact > separation > float(gap[0]["met"])


def enter(chain, previous, ignition):
    p61 = chain.leg(previous, "entry-p61", (CREW / "p61.lua").read_text(), 12000, .0625,
                    "entry-cmc.csv", "p62_waiting_for_service_module_sep")
    met = float(field(p61, "MISSNTIME"))
    telemetry = (CREW / "entry-telemetry.lua").read_text()
    script = f"local initialMET={met}\nlocal separationMET={ignition+385}\n" + telemetry + (CREW / "p62.lua").read_text()
    p62 = chain.leg(p61, "entry-separation", script, 16000, .05, "deorbit-to-entry.csv", "cm_rcs_transfer_confirmed")
    met = float(field(p62, "MISSNTIME"))
    script = f"local initialMET={met}\n" + telemetry + (CREW / "p63.lua").read_text()
    attitude = chain.leg(p62, "entry-attitude", script, 18000, .025, "deorbit-to-entry.csv", "p63_entry_started")
    met = float(field(attitude, "MISSNTIME"))
    script = replace_once(fixture(chain, "entry-manual-attitude"), r"local initialMET = [\d.]+", f"local initialMET={met}")
    script = replace_once(script, r"oapi.simulateimmediatekey\(amount>0 and chosen\[2\] or chosen\[3\]\)",
                          "oapi.simulateimmediatekey(amount>0 and chosen[2] or chosen[3],OAPI_KEY.LALT)")
    descent = chain.leg(attitude, "entry-splashdown", script, 150000, .025, "deorbit-to-entry.csv", "splashdown")
    recovery = chain.leg(descent, "entry-recovery", (CREW / "recovery.lua").read_text(), 6000, .05,
                         "recovery.csv", "settled_recovery")
    verify_entry(p62, recovery)
    return recovery


def fly(chain, previous):
    from apollo7_four import coast, prepare_p40
    from apollo7_middle import uplink_and_p30
    pad = coast(chain, previous, 8)
    confirmed = uplink_and_p30(chain, pad, 8)
    preburn = prepare_p40(chain, confirmed, pad, 8)
    deorbit = burn(chain, preburn, pad)
    return enter(chain, deorbit, float(field(pad, "MCC_AP7MNV_GETI")))
