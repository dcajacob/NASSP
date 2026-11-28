"""Fly Apollo 7 from the original T-20 minute countdown."""
from pathlib import Path
import json
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
COUNTDOWN_SHA256 = "8dc1c9a2a19bd8ae260085c039100ad1f8d6e242ef5eea4e3710e4b134f0a882"


def countdown_input():
    if digest(COUNTDOWN) != COUNTDOWN_SHA256:
        raise ValueError("The original T-20 minute scenario changed")
    return COUNTDOWN.read_bytes().replace(b"END_ENVIRONMENT", TOWER + b"\r\nEND_ENVIRONMENT", 1)


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


def verify(output):
    insertion = output / "countdown"
    result = insertion_result(insertion)
    stages = [("csm-separation", "insertion-to-csm.csv", "separate_orbits"),
              ("phasing", "phasing-flight.csv", "phasing_complete")]
    previous = insertion
    records = []
    for stage, telemetry, event in stages:
        current = output / stage
        records.append(check_leg(previous, current, telemetry, event))
        previous = current
    if records != json.loads((output / "lineage.json").read_text()):
        raise ValueError("The recorded handoffs differ from the flown scenarios")
    result.update(handoffs=records, retrograde_phasing_m_s=float(rows(previous / "phasing-flight.csv")[-1]["retro_dv"]))
    if not .5 < result["retrograde_phasing_m_s"] < .65:
        raise ValueError("Phasing impulse outside limits")
    (output / "phasing-results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    inputs, output = map(Path, sys.argv[1:])
    chain = Chain(inputs, output)
    separation_and_phasing(chain, countdown(chain))
    verify(chain.output)
