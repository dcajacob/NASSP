"""Fly, save and reload the frozen Columbia/Eagle lunar orbit on the CI host."""
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

inputs, output = (Path(arg).resolve() for arg in sys.argv[1:])
runtime = inputs / "runtime"
engine = runtime / "engine"
manifest = json.loads((inputs / "launcher-manifest.json").read_text())
scene = "resources/Scenarios/Apollo 11 - Native Linux Saves/04 - Lunar orbit.scn"
fixture = next(item for item in manifest if item["scenario"] == scene)
initial = runtime / scene
if hashlib.sha256(initial.read_bytes()).hexdigest() != fixture["scenario_sha256"]:
    raise ValueError("Frozen Apollo 11 input differs")
revision = (inputs / "orbiter-source.txt").read_text().strip()
if revision != os.environ["ORBITER_REVISION"]:
    raise ValueError("Wrong Orbiter source revision")
env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE="1", LP_NUM_THREADS="2", SDL_AUDIODRIVER="dummy",
           PULSE_SERVER="unix:/nonexistent", XDG_SESSION_TYPE="x11")
for key in ("LD_LIBRARY_PATH", "WAYLAND_DISPLAY"):
    env.pop(key, None)


def mjd(path):
    return float(re.search(r"^\s*Date MJD\s+(\S+)", path.read_text(errors="replace"), re.M)[1])


def flight(name, scenario):
    case = output / name
    case.mkdir(parents=True)
    replay = case / "replay.csv"
    replay.write_text("tick,phase,action,value\n8,after,save,0\n")
    saved = case / "saved.scn"
    args = [engine / "run-orbiter", "--scenario", scenario, "--config", runtime / "Orbiter.cfg",
            "--assets", runtime / "resources", "--data", runtime / "celestial-data",
            "--modules", engine / "NativeModules", "--planets", runtime / "planet-archives",
            "--keymap", runtime / "Keymap.cfg", "--save", saved, "--evidence", case,
            "--replay", replay, "--ticks", "12", "--fixed-step", "0.0166666666666667",
            "--render-every", "1", "--run"]
    with (case / "run.log").open("wb") as log:
        subprocess.run(args, cwd=case, stdout=log, stderr=subprocess.STDOUT, env=env,
                       check=True, timeout=120)
    graphics = json.loads((case / "graphics-lifecycle.json").read_text())
    if graphics["successful_presents"] != 12 or not graphics["context_deleted"]:
        raise ValueError(f"{name}: incomplete graphics session: {graphics}")
    expected = {"Columbia": "Eagle", "Eagle": "Columbia"}
    seen = set()
    with (case / "flight-state.csv").open() as stream:
        for row in csv.DictReader(stream):
            ship = row["object"]
            if ship in expected:
                if row["dock"] != expected[ship] or not all(math.isfinite(float(row[k])) for k in
                        ("rx", "ry", "rz", "vx", "vy", "vz", "mass", "fuel", "mjd")):
                    raise ValueError(f"{name}: invalid orbital or docking state for {ship}")
                seen.add(ship)
    if seen != expected.keys() or mjd(saved) <= mjd(scenario):
        raise ValueError(f"{name}: missing spacecraft or simulation time did not advance")
    return saved


first = flight("lunar-save", initial)
second = flight("lunar-reload", first)
result = dict(orbiter_source=revision, nassp_source=os.environ.get("GITHUB_SHA"),
              executable_sha256=hashlib.sha256((engine / "orbiter-production").read_bytes()).hexdigest(),
              sdk_header_sha256=hashlib.sha256((engine / "native-sdk/OrbiterNativeBuild.h").read_bytes()).hexdigest(),
              scenario=scene, scenario_sha256=fixture["scenario_sha256"], muted=True,
              docked=["Columbia", "Eagle"], saved_mjd=mjd(first), reloaded_save_mjd=mjd(second),
              frames_per_process=12)
(output / "lunar-smoke.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
