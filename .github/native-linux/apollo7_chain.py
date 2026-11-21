"""Replay consecutive Apollo 7 crew procedures from the corrected SPS-3 save."""
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


HERE = Path(__file__).resolve().parent
SEED = HERE / "apollo7_seed"
SEED_SHA256 = "b6da432e88ece2a8722d7be0be81434153f345ea6e1c5606161bb8cb334737c3"
SCRIPT = b"  Script ProjectApollo/apollo7-linked-replay"
EMPTY_KEYS = "tick,phase,action,value\n"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def input_bytes(previous):
    raw = (previous / "saved.scn").read_bytes()
    result, count = re.subn(rb"^  Script ProjectApollo/[^\r\n]+", SCRIPT, raw, flags=re.M)
    if count != 1 or not raw.rstrip().endswith(b"END_SHIPS"):
        raise ValueError(f"Incomplete handoff from {previous}")
    return result


def clock(directory):
    raw = (directory / "saved.scn").read_bytes()
    csm = re.search(rb"^AS-205:[^\n]*\n(.*?)^END\r?$", raw, re.M | re.S)
    return float(re.search(rb"^  MISSNTIME (\S+)", csm[1], re.M)[1])


def check_leg(previous, directory, csv_name, marker):
    if (directory / "input.scn").read_bytes() != input_bytes(previous):
        raise ValueError(f"Broken save lineage at {directory}")
    log = (directory / "console.log").read_text(errors="replace")
    if ("Native OpenGL renderer:" not in log or "LuaCall" in log
            or "Saved finalized production scenario:" not in log):
        raise ValueError(f"Unfinished native OpenGL session in {directory}/console.log")
    with (directory / csv_name).open() as stream:
        events = csv.reader(stream)
        if not any(marker in row for row in events):
            raise ValueError(f"{directory.name}: missing {marker} in {csv_name}")
    if not (directory / "saved.scn").read_bytes().rstrip().endswith(b"END_SHIPS"):
        raise ValueError(f"Truncated save in {directory}")
    if clock(directory) <= clock(previous):
        raise ValueError(f"Mission time failed to advance at {directory}")
    return dict(stage=directory.name, parent=previous.name, previous_sha256=digest(previous / "saved.scn"),
                input_sha256=digest(directory / "input.scn"), save_sha256=digest(directory / "saved.scn"),
                start_get=clock(previous), end_get=clock(directory), telemetry=csv_name, event=marker)


class Chain:
    def __init__(self, inputs, output):
        self.inputs = Path(inputs).resolve()
        self.runtime = self.inputs / "runtime"
        self.output = Path(output).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.records = []

    def leg(self, previous_dir, slug, lua_text, ticks, step, csv_name, marker, replay=None):
        directory = self.output / slug
        directory.mkdir()
        (directory / "input.scn").write_bytes(input_bytes(previous_dir))
        (directory / "crew.lua").write_text(lua_text)
        (directory / "replay.csv").write_text(EMPTY_KEYS if replay is None else replay)
        engine = self.runtime / "engine"
        args = [engine / "run-orbiter", "--assets", self.runtime / "resources", "--data",
                self.runtime / "celestial-data", "--modules", engine / "NativeModules",
                "--planets", self.runtime / "planet-archives", "--config", self.runtime / "Orbiter.cfg",
                "--xrsound-assets", self.runtime / "resources", "--scenario", "input.scn",
                "--save", "saved.scn", "--replay", "replay.csv", "--ticks", str(ticks),
                "--fixed-step", str(step), "--render-every", "257", "--run"]
        env = os.environ.copy()
        for key in ("WAYLAND_DISPLAY", "LD_LIBRARY_PATH"):
            env.pop(key, None)
        print(f"Flying {slug} from {previous_dir.name}", flush=True)
        with (directory / "console.log").open("wb") as log:
            subprocess.run(args, cwd=directory, env=env, stdin=subprocess.DEVNULL, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        record = check_leg(previous_dir, directory, csv_name, marker)
        self.records.append(record)
        (self.output / "lineage.json").write_text(json.dumps(self.records, indent=2) + "\n")
        print(f"{slug}: {marker} at GET {record['end_get']:.2f}", flush=True)
        return directory


def verify(output):
    from apollo7_entry import verify_entry

    if digest(SEED / "saved.scn") != SEED_SHA256:
        raise ValueError("The corrected SPS-3 reference save has changed")
    previous = SEED
    records = json.loads((output / "lineage.json").read_text())
    for record in records:
        directory = output / record["stage"]
        expected = check_leg(previous, directory, record["telemetry"], record["event"])
        if expected != record:
            raise ValueError(f"Inconsistent flight receipt for {directory}")
        previous = directory
    burns = [item["stage"] for item in records if item["stage"].endswith("-burn")]
    if burns != [f"sps{n}-burn" for n in range(4, 9)]:
        raise ValueError(f"Incomplete burn sequence: {burns}")
    if previous.name != "entry-splashdown":
        raise ValueError("Missing splashdown")
    verify_entry(output / "entry-separation", previous)
    print(f"{len(records)} linked flights passed from SPS-3 to splashdown at GET {clock(previous):.2f}.")


def main(inputs, output):
    from apollo7_four import fly as sps4
    from apollo7_middle import fly as sps5_through_7
    from apollo7_entry import fly as sps8_and_entry

    if digest(SEED / "saved.scn") != SEED_SHA256:
        raise ValueError("Wrong SPS-3 save")
    chain = Chain(inputs, output)
    previous = SEED
    for fly in (sps4, sps5_through_7, sps8_and_entry):
        previous = fly(chain, previous)
    verify(chain.output)


if __name__ == "__main__":
    if sys.argv[1] == "--verify":
        verify(Path(sys.argv[2]))
    else:
        main(*sys.argv[1:])
