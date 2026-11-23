import csv
import json
import re
import sys
from pathlib import Path

from replay_checks import verify_mission_replays


def erasable(path):
    agc = path.read_text().split("\nIntrepid:", 1)[1].split("\nAGC_BEGIN\n", 1)[1].split("\nAGC_END", 1)[0]
    return {
        int(address, 8): int(word, 8) & 0o77777
        for address, word in re.findall(r"EMEM([0-7]+) ([0-7]+)", agc)
    }


def verify_p27(directory):
    initial = directory / "input.scn"
    packet = re.search(r"^  MCC_upString (\S+)", initial.read_text(), re.M)[1]
    loads = {}
    for count, address, words in re.findall(r"V71E([0-7]+)E([0-7]+)E([0-7E]+)V33E", packet):
        values = [int(value, 8) for value in words.rstrip("E").split("E")]
        assert len(values) + 2 == int(count, 8)
        loads[address] = values
    assert list(loads) == ["1501", "3433"]
    nav, target = loads.values()
    assert len(nav) == 15 and len(target) == 8 and nav[0] == 0o77775
    memory = erasable(directory / "saved.scn")
    assert [memory.get(0o1626 + i, 0) for i in range(12)] == nav[1:13]
    assert [memory.get(0o3433 + i, 0) for i in range(8)] == target
    log = (directory / "console.log").read_text()
    sessions = re.search(r"P27 starts and completions\s+(\d+)\s+(\d+)", log)
    assert sessions and sessions.groups() == ("2", "2")
    return {"completed": 2, "ignition_get_s": (target[-2] * 16384 + target[-1]) / 100}


def events_at(path):
    with path.open() as stream:
        return {row["event"]: row for row in csv.DictReader(stream)}


def verify_flights(flight):
    results = {}
    name = "a12-intrepid-imu-preserved-capcom-load"
    results[name] = verify_p27(flight / name)

    for step in ("125ms", "60hz"):
        name = f"apollo8-ullage-fixed-{step}-axial"
        events = events_at(flight / name / "direct-ullage-step.csv")
        thrust = {event: float(row["axial_thrust_n"]) for event, row in events.items()}
        assert thrust["off"] == thrust["released"] == 0 and 874 < thrust["held"] < 875, thrust
        results[name] = thrust

    name = "apollo8-flown-first-midcourse-fixed"
    tli = (flight / name / "saved.scn").read_text()
    assert re.search(r"^\s*MCC_MissionState 24\s*$", tli, re.M)
    assert re.search(r"^\s*MCC_SubState 2\s*$", tli, re.M)
    results[name] = {"mcc_state": 24, "mcc_substate": 2}

    name = "apollo12-intrepid-guided-approach-reload-shutdown"
    landing = flight / name
    events = events_at(landing / "touchdown.csv")
    contact = events["contact"]
    assert events["reload"]["program"] == "64" and contact["program"] == "65"
    assert float(contact["horiz_m_s"]) < .5
    assert -.99 < float(contact["radial_m_s"]) < -.9
    lm = (landing / "saved.scn").read_text().split("\nIntrepid:", 1)[1].split("\nEND\n", 1)[0]
    assert "STATUS Landed Moon" in lm and "RCSMODE 0" in lm
    reserves = re.search(r"^  PRPLEVEL (.*)$", lm, re.M)[1]
    assert "1:0.587" in reserves and "2:0.568" in reserves, reserves
    results[name] = {"touchdown": contact, "propellant_after_shutdown": reserves}
    return results


def verify_launcher(manifest_path, output):
    manifest = json.loads(Path(manifest_path).read_text())
    launcher = json.loads((output / "launcher/results.json").read_text())
    assert len(manifest) == len({row["path"] for row in launcher}) == len(launcher) == 53
    for fixture, row in zip(manifest, launcher):
        assert fixture["scenario"] == row["path"] and row["result"] == "passed", row
        assert (row["simulated_seconds"] is not None) == fixture["interactive"], row
        if fixture["interactive"]:
            assert row["simulated_seconds"] > 0 and row["audio_backend"] == "PulseAudio", row
    interactive = sum(row["simulated_seconds"] is not None for row in launcher)
    assert interactive == 26

    print(f"{len(launcher)} native OpenGL launcher checks passed, including {interactive} interactive checks.")
    return {"launcher_passed": len(launcher), "interactive_launcher_passed": interactive}


def main(manifest_path, output, suite="baseline"):
    output = Path(output)
    if suite == "apollo7-linked-return":
        from apollo7_chain import verify
        verify(output / "linked-return")
        return
    flight = output / "flight"
    cases = []
    for line in Path(__file__).with_name("replays.tsv").read_text().splitlines():
        group, case, *_ = line.split("\t")
        if group == suite:
            cases.append(case)
    assert cases and set(cases) == {directory.name for directory in flight.iterdir() if directory.is_dir()}, suite
    for case in cases:
        directory = flight / case
        log = (directory / "console.log").read_text(errors="replace")
        assert "Native OpenGL renderer:" in log and "LuaCall" not in log, case
        assert "Saved finalized production scenario:" in log, case
        assert b"END_SHIPS" in (directory / "saved.scn").read_bytes(), case
    if suite == "baseline":
        results = verify_launcher(manifest_path, output)
        replays = verify_flights(flight)
    else:
        results = {}
        replays = verify_mission_replays(flight, cases)
    results["flight_replays"] = replays
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"{len(replays)} flight replays passed ({suite}).")
    for case, result in replays.items():
        if note := result.get("qualification_note"):
            print(f"{case} — {note}")


if __name__ == "__main__":
    main(*sys.argv[1:])
