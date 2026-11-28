"""Fly Apollo 7 from the original T-20 minute countdown."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import sys

from apollo7_chain import Chain, check_leg, clock, digest, saved_orbit
from apollo7_checks import rows
from apollo7_four import CREW

SAVE_AND_EXIT = """
oapi.simulatebufferedkey(OAPI_KEY.S,OAPI_KEY.LCONTROL)
proc.wait_frames(5)
oapi.simulatebufferedkey(OAPI_KEY.Q,OAPI_KEY.LCONTROL)
"""


SOURCE = Path(__file__).resolve().parents[2]
COUNTDOWN = (SOURCE / "Scenarios/Project Apollo - NASSP/Apollo - Mission Scenarios/Apollo 7"
             / "Apollo 7 - 01 - Launch T-20m.scn")
TOWER = b"  Script ProjectApollo/Native-Mission-Qualification/apollo7-tower-jettison"
COUNTDOWN_SHA256 = "e08f6d04adee8ab464a1311d0501d749b870b35b466c2b67c29af645d91715a8"


def countdown_input():
    original = COUNTDOWN.read_bytes().replace(b"\r\n", b"\n")
    if hashlib.sha256(original).hexdigest() != COUNTDOWN_SHA256:
        raise ValueError("The original T-20 minute scenario changed")
    return original.replace(b"\n", b"\r\n").replace(b"END_ENVIRONMENT", TOWER + b"\r\nEND_ENVIRONMENT", 1)


def insertion_result(directory):
    if (directory / "input.scn").read_bytes() != countdown_input():
        raise ValueError("The flown countdown differs from the original launch scenario")
    log = (directory / "console.log").read_text(errors="replace")
    if ("Native OpenGL renderer:" not in log or "LuaCall" in log
            or "Saved finalized production scenario:" not in log):
        raise ValueError("Incomplete countdown or ascent")
    samples = rows(directory / "crew-ascent.csv")
    before, after = samples[:2]
    if (before["event"], before["tower_vessel"], after["event"], after["tower_vessel"]) != (
            "before-jettison", "0", "after-jettison", "1"):
        raise ValueError("Tower jettison did not occur")
    perigee, apogee = saved_orbit(directory)
    if not (150000 < perigee < apogee < 400000 and 775 < clock(directory) < 785):
        raise ValueError(f"Unexpected Saturn IB insertion: {perigee}, {apogee}, {clock(directory)}")
    return dict(stock_sha256=COUNTDOWN_SHA256, input_sha256=digest(directory / "input.scn"),
                insertion_sha256=digest(directory / "saved.scn"), insertion_get=clock(directory),
                perigee_m=perigee, apogee_m=apogee)


def countdown(chain):
    directory = chain.output / "countdown"
    directory.mkdir()
    fixture = chain.inputs / "flight/apollo7-original-crew-ascent-current"
    (directory / "input.scn").write_bytes(countdown_input())
    shutil.copyfile(fixture / "replay.csv", directory / "replay.csv")
    chain.run_session(directory, 16000, .0625, ("--keymap", chain.runtime / "Keymap.cfg"))
    insertion_result(directory)
    return directory


def separation_and_phasing(chain, insertion):
    procedure = (CREW / "separation.lua").read_text()
    # MCC prepares its first navigation uplink shortly after physical separation.
    procedure += "\nproc.wait_simtime(10270 - initialMET)\n" + SAVE_AND_EXIT
    separate = chain.leg(insertion, "csm-separation",
                         f"local initialMET={clock(insertion)}\n" + procedure,
                         7000, .25, "insertion-to-csm.csv", "separate_orbits")
    procedure = (CREW / "phasing.lua").read_text()
    return chain.leg(separate, "phasing", f"local startMET={clock(separate)}\n" + procedure + SAVE_AND_EXIT,
                     13000, .125, "phasing-flight.csv", "phasing_complete")


def advisory(chain, previous, slug, get, state, uplink=True):
    header = (f"local start_get,advisory_get,advisory_state={clock(previous)},{get},{state}\n"
              f"local require_uplink={str(uplink).lower()}\n")
    return chain.leg(previous, slug, header + (CREW / "early-coast.lua").read_text() + SAVE_AND_EXIT,
                     50000, .125, "coast.csv", "advisory")


def do_uplink(chain, pad, slug, procedure):
    from apollo7_middle import uplink_script, saved
    return chain.leg(pad, slug, uplink_script(saved(pad), procedure), 14000, .125,
                     "uplink.csv", "target_uplink_verified")


def second_phasing(chain, pad):
    from apollo7_middle import saved, field
    raw = saved(pad)
    if "  MCC_AP7MNV_purpose PHASING 2\n" not in raw:
        if field(raw,"MCC_scrubbed") != "1" or field(raw,"MCC_MissionState") != "20":
            raise ValueError("Unexpected second phasing advisory")
        return pad
    if "+X thrusters" not in field(raw,"MCC_AP7MNV_remarks"):
        raise ValueError("Second phasing needs an SPS maneuver")
    x,y,z = map(float,field(raw,"MCC_AP7MNV_dV").split())
    if max(abs(y),abs(z)) > .01:
        raise ValueError("Second phasing has an unexpected cross-track or radial component")
    header = (f"local initial_get,tig={clock(pad)},{field(raw,'MCC_AP7MNV_GETI')}\n"
              f"local target_dv,duration={x * .3048},{field(raw,'MCC_AP7MNV_burntime')}\n")
    return chain.leg(pad, "phasing-two", header + (CREW / "phasing-two.lua").read_text() + SAVE_AND_EXIT,
                     24000, .0625, "phasing-two.csv", "phasing_two_complete")


def fly_phasing(chain):
    first = separation_and_phasing(chain, countdown(chain))
    pad = advisory(chain, first, "block-deorbit-pad", 17220, 17)
    update = do_uplink(chain, pad, "block-deorbit-uplink", 8)
    pad = advisory(chain, update, "second-phasing-advisory", 51600, 20, False)
    return second_phasing(chain, pad)


def rendezvous_burn(chain, pad, number, purpose, *, realign=True, voice_pad=False):
    from apollo7_four import prepare_p40
    from apollo7_middle import burn_script, field, p30, saved, uplink_and_p30
    raw = saved(pad)
    if field(raw, "MCC_AP7MNV_purpose") != purpose:
        raise ValueError(f"Missing live {purpose} maneuver PAD")
    readback = p30(chain, pad, pad, number, manual_entry=True) if voice_pad else uplink_and_p30(chain, pad, number)
    ready = prepare_p40(chain, readback, pad, number, realign=realign)
    return chain.leg(ready, f"sps{number}-burn", burn_script(chain.runtime, saved(ready), raw, number),
                     75000, .0625, "sps6-p40.csv", "linked_burn_verified")


def nsr_and_approach(chain, parent):
    from apollo7_middle import field, saved, table
    nsr = advisory(chain, parent, "nsr-pad", max(clock(parent)+1, 97900), 32, False)
    voice = "  MCC_upString " not in saved(nsr)
    burn = rendezvous_burn(chain, nsr, 2, "NSR", realign=False, voice_pad=voice)
    tpi = advisory(chain, burn, "tpi-pad", 103900, 33, False)
    raw = saved(tpi)
    tig = float(field(raw, "MCC_AP7TPI_GETI"))
    fps = [float(x) for x in field(raw, "MCC_AP7TPI_Vg").split()]
    dv = [x*.3048 for x in fps]
    if len(dv) != 3 or not 500 < tig-clock(tpi) < 7000:
        raise ValueError("Invalid TPI ignition time or velocity vector")
    header = f"local tig,deltaV,manual_entry={tig},{table(fps)},true\n"
    readback = chain.leg(tpi, "tpi-p30", header + (CREW / "p30.lua").read_text(), 5000, .125,
                         "p30.csv", "p30_pad_verified")
    return terminal_approach(chain, readback, tig, dv)


def terminal_approach(chain, readback, tig, dv):
    from apollo7_middle import table
    controls = (CREW / "rendezvous-controls.lua").read_text()
    previous = readback
    for name, event in (("tpi","tpi"), ("rendezvous","rendezvous_complete")):
        header = f"local tig,start_get,pad_dv={tig},{clock(previous)},{table(dv)}\n"
        previous = chain.leg(previous, name, header + controls + (CREW / (name+".lua")).read_text()
                             + SAVE_AND_EXIT, 100000, .0625, "rendezvous.csv", event)
    return previous


def fly_sps3(chain, previous):
    from apollo7_four import coast, prepare_p40
    from apollo7_middle import field, saved, substitute, table, uplink_and_p30
    pad = coast(chain, previous, 3)
    raw = saved(pad)
    def value(name):
        return float(field(raw, "MCC_AP7MNV_" + name))
    p00 = uplink_and_p30(chain, pad, 3)
    ready = prepare_p40(chain, p00, pad, 3)
    directory = chain.runtime / "resources/Script/ProjectApollo"
    source = (directory / "apollo7-countdown-sps3-scs-burn-rate-mode.lua").read_text()
    source = substitute(source, r"^local timeToIgnition = .*", f"local timeToIgnition = {value('GETI')-clock(ready)}")
    source = substitute(source, r'^set\("EMSDvDisplay",\d+\)', f'set("EMSDvDisplay",{round(value("Vc")*10)})')
    source = substitute(source, r"^local orbitMatches=.*",
                        "local orbitMatches=math.abs(orbit.PeD-radius-padPerigee)<15000 "
                        "and math.abs(orbit.ApD-radius-padApogee)<15000")
    dv = [float(x)*.3048 for x in field(raw, "MCC_AP7MNV_dV").split()]
    header = (f"local padLVLH,padMagnitude={table(dv)},{math.hypot(*dv)}\n"
              f"local padPerigee,padApogee={value('HP')*1852},{value('HA')*1852}\n")
    source = substitute(source, r'^at\(-30,"ullage"\)', 'at(-30,"ullage")\n'+(CREW / "burn-integral.lua").read_text())
    source = substitute(source, r'^local originalMass=', 'local ignitionMass=ship:get_mass()\nlocal originalMass=')
    source = substitute(source, r'^reportState\("sps3_completed"\)',
                        'local ignitionPropellant,impulse=originalMass,ullageImpulse\n'
                        + (CREW / "burn-result.lua").read_text() + '\nreportState("sps3_completed")')
    burn = chain.leg(ready, "sps3-burn", header + source, 75000, .0625, "sps3-scs.csv", "sps3_completed")
    return chain.leg(burn, "sps3-postburn", (directory / "apollo7-sps3-postburn-replay.lua").read_text(),
                     14000, .0625, "postburn.csv", "post_sps3_continuation_complete")


def fly_from_phasing(chain, previous):
    preliminary = advisory(chain, previous, "ncc1-preliminary", 80900, 22)
    update = do_uplink(chain, preliminary, "ncc1-preliminary-uplink", 1)
    final = advisory(chain, update, "ncc1-pad", 91860, 30)
    cutoff = rendezvous_burn(chain, final, 1, "NCC-1")
    ncc2 = advisory(chain, cutoff, "ncc2-advisory", 97530, 31, False)
    from apollo7_middle import field, saved
    raw = saved(ncc2)
    if field(raw, "MCC_scrubbed") == "0":
        if "P40 SPS" not in field(raw, "MCC_AP7MNV_remarks"):
            raise ValueError("Unexpected NCC-2 engine selection")
        ncc2 = rendezvous_burn(chain, ncc2, "ncc2", "NCC-2", realign=False)
    return fly_sps3(chain, nsr_and_approach(chain, ncc2))


def early_burn_result(output, number, pad_name):
    from apollo7_middle import saved, field
    pad = saved(output / pad_name)
    prefix = f"sps{number}-"
    readback = {row["phase"]: row for row in rows(output / (prefix+"p30") / "p30.csv")}
    r = readback["ignition_time"]
    ignition = int(r["r1"])*3600 + int(r["r2"])*60 + int(r["r3"])/100
    target = [float(x)*.3048 for x in field(pad,"MCC_AP7MNV_dV").split()]
    cmc = [int(readback["delta_v"][key])*.03048 for key in ("r1","r2","r3")]
    burn, = rows(output / (prefix+"burn") / "burn-result.csv")
    measured = [float(burn[f"achieved_{axis}_m_s"]) for axis in "xyz"]
    if (abs(ignition-float(field(pad,"MCC_AP7MNV_GETI")))>.03 or math.dist(cmc,target)>.08
            or math.dist(measured,target)>max(2,.03*math.hypot(*target))):
        raise ValueError(f"{pad_name}: CMC and measured impulse must agree with the live PAD")
    return dict(purpose=field(pad,"MCC_AP7MNV_purpose"), tig_s=ignition, target_m_s=target,
                measured_m_s=measured, vector_error_m_s=math.dist(measured,target),
                sps_used_kg=float(burn["sps_kg"]))


def verify(output, full=False):
    insertion = output / "countdown"
    result = insertion_result(insertion)
    stages = [("csm-separation", "insertion-to-csm.csv", "separate_orbits"),
              ("phasing", "phasing-flight.csv", "phasing_complete"),
              ("block-deorbit-pad", "coast.csv", "advisory"),
              ("block-deorbit-uplink", "uplink.csv", "target_uplink_verified"),
              ("second-phasing-advisory", "coast.csv", "advisory")]
    from apollo7_middle import saved, field
    second = saved(output / "second-phasing-advisory")
    if field(second, "MCC_scrubbed") == "0":
        stages.append(("phasing-two", "phasing-two.csv", "phasing_two_complete"))
        cutoff = rows(output / "phasing-two/phasing-two.csv")[-1]
        if (float(cutoff["vector_error_m_s"]) >= .15 or
                abs(float(cutoff["target_m_s"]) - .3048*float(field(second, "MCC_AP7MNV_dV").split()[0])) > .0001):
            raise ValueError("Second phasing does not match its live PAD")
    elif field(second, "MCC_scrubbed") != "1":
        raise ValueError("Invalid MCC scrub decision")
    if full:
        stages.extend([("ncc1-preliminary","coast.csv","advisory"),
                       ("ncc1-preliminary-uplink","uplink.csv","target_uplink_verified"),
                       ("ncc1-pad","coast.csv","advisory")])
        def powered(number, uplink, align):
            prefix = f"sps{number}-"
            if uplink:
                stages.append((prefix+"uplink","uplink.csv","target_uplink_verified"))
            stages.append((prefix+"p30","p30.csv","p30_pad_verified"))
            if align:
                stages.append((prefix+"alignment","alignment.csv","platform_reference_ready"))
            stages.append((prefix+"prepare-p40","prepare-p40.csv","ready_for_slew"))
            stages.append((prefix+"burn","sps3-scs.csv" if number==3 else "sps6-p40.csv",
                           "sps3_completed" if number==3 else "linked_burn_verified"))
        powered(1, True, True)
        stages.append(("ncc2-advisory","coast.csv","advisory"))
        if field(saved(output/"ncc2-advisory"),"MCC_scrubbed") == "0":
            powered("ncc2", True, False)
        stages.append(("nsr-pad","coast.csv","advisory"))
        powered(2, "  MCC_upString " in saved(output/"nsr-pad"), False)
        stages.extend([("tpi-pad","coast.csv","advisory"), ("tpi-p30","p30.csv","p30_pad_verified"),
                       ("tpi","rendezvous.csv","tpi"), ("rendezvous","rendezvous.csv","rendezvous_complete"),
                       ("sps3-coast","coast.csv","maneuver_pad_ready")])
        powered(3, True, True)
        stages.append(("sps3-postburn","postburn.csv","post_sps3_continuation_complete"))
    previous = insertion
    records = []
    for stage, telemetry, event in stages:
        current = output / stage
        records.append(check_leg(previous, current, telemetry, event))
        previous = current
    if records != json.loads((output / "lineage.json").read_text()):
        raise ValueError("The recorded handoffs differ from the flown scenarios")
    result.update(handoffs=records, retrograde_phasing_m_s=float(rows(output / "phasing/phasing-flight.csv")[-1]["retro_dv"]))
    if not .5 < result["retrograde_phasing_m_s"] < .65:
        raise ValueError("Phasing impulse outside limits")
    if full:
        from apollo7_checks import verify_sps3
        from apollo7_chain import verify as verify_return
        maneuvers = [(1,"ncc1-pad"), (2,"nsr-pad"), (3,"sps3-coast")]
        if field(saved(output/"ncc2-advisory"),"MCC_scrubbed") == "0":
            maneuvers.insert(1, ("ncc2","ncc2-advisory"))
        result["early_maneuvers"] = [early_burn_result(output,n,pad) for n,pad in maneuvers]
        station, = [r for r in rows(output/"rendezvous/rendezvous.csv") if r["event"] == "stationkeeping"]
        if not (150 < float(station["range_m"]) < 850 and float(station["relative_speed_m_s"]) < .45):
            raise ValueError("Missed S-IVB stationkeeping limits")
        result["stationkeeping"] = station
        result["sps3"] = verify_sps3(output/"sps3-burn", output/"sps3-coast", previous)
        verify_return(output/"return", previous)
        recovery = json.loads((output/"return/results.json").read_text())
        if recovery["seed_sha256"] != records[-1]["save_sha256"]:
            raise ValueError("Return did not start from the flown SPS-3 coast")
        result["return"] = recovery
    name = "countdown-to-recovery.json" if full else "phasing-results.json"
    (output / name).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    full = "--full" in sys.argv[3:]
    inputs, output = map(Path, sys.argv[1:3])
    chain = Chain(inputs, output)
    phasing = fly_phasing(chain)
    if full:
        from apollo7_chain import main as fly_return
        seed = fly_from_phasing(chain, phasing)
        fly_return(chain.inputs, chain.output/"return", seed)
    verify(chain.output, full)
