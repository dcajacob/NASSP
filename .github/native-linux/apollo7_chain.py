"""Replay consecutive Apollo 7 crew procedures from the corrected SPS-3 save."""
import csv
import hashlib
import json
import math
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
        self.engine_sha = digest(self.runtime / "engine/orbiter-production")

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
        # Orbiter keeps simulating after a crew script raises an error. Stop
        # that leg immediately so it cannot coast past its recovery window.
        log_path = directory / "console.log"
        with log_path.open("wb") as log, log_path.open(errors="replace") as reader:
            with subprocess.Popen(["stdbuf", "-oL", "-eL", *args], cwd=directory, env=env,
                                  stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT) as process:
                while process.poll() is None:
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        for line in reader:
                            if "LuaCall" in line:
                                process.terminate()
                                raise RuntimeError(f"{slug}: {line.strip()}")
                if process.returncode:
                    raise subprocess.CalledProcessError(process.returncode, args)
        record = check_leg(previous_dir, directory, csv_name, marker)
        self.records.append(record)
        (self.output / "lineage.json").write_text(json.dumps(self.records, indent=2) + "\n")
        print(f"{slug}: {marker} at GET {record['end_get']:.2f}", flush=True)
        return directory


def saved_orbit(directory):
    # Sol_VirtualAGC selects Config/ProjectApollo/Earth_VirtualAGC.cfg.
    # Reconstruct the osculating apsides from the serialized flight state.
    mu = 6.67259e-11 * 5.97374033e24
    radius = 6373338.
    raw = (directory / "saved.scn").read_text(encoding="latin-1")
    csm = re.search(r"^AS-205:.*?\n(.*?)^END$", raw, re.M | re.S)[1]
    if "  STATUS Orbiting Earth\n" not in csm:
        raise ValueError(f"{directory.name}: expected a geocentric cutoff state")
    r, v = (list(map(float, re.search(r"^  " + key + r" (.+)$", csm, re.M)[1].split()))
            for key in ("RPOS", "RVEL"))
    distance = math.hypot(*r)
    speed2 = sum(x*x for x in v)
    rv = sum(x*y for x,y in zip(r, v, strict=True))
    a = 1 / (2 / distance - speed2 / mu)
    h2 = distance**2 * speed2 - rv**2
    eccentricity = math.sqrt(1 - h2 / (mu * a))
    return a*(1 - eccentricity) - radius, a*(1 + eccentricity) - radius


def burn_measurements(output, number):
    from apollo7_checks import rows
    from apollo7_middle import field

    prefix = f"sps{number}"
    pad_dir = output / (prefix + "-coast")
    if number == 5 and (output / "sps5-retarget").is_dir():
        pad_dir = output / "sps5-retarget"
    pad = (pad_dir / "saved.scn").read_text(encoding="latin-1")
    readback = {row["phase"]: row for row in rows(output / (prefix + "-p30") / "p30.csv")}
    tig = float(field(pad, "MCC_AP7MNV_GETI"))
    dv = list(map(float, field(pad, "MCC_AP7MNV_dV").split()))
    time = readback["ignition_time"]
    cmc_tig = 3600 * int(time["r1"]) + 60 * int(time["r2"]) + int(time["r3"]) / 100
    cmc_dv = [int(readback["delta_v"][key]) / 10 for key in ("r1", "r2", "r3")]
    if abs(cmc_tig - tig) > .03 or any(abs(a-b) > .15 for a,b in zip(dv, cmc_dv, strict=True)):
        raise ValueError(f"{prefix}: AGC readback disagrees with the maneuver PAD")
    names = {4: "sps4-p40.csv", 5: "sps5-manual-tvc.csv", 6: "sps6-p40.csv",
             7: "sps7-scs.csv", 8: "retrofire-burn.csv"}
    samples = rows(output / (prefix + "-burn") / names[number])
    last = samples[-1]
    debit = float(samples[0]["sps_mass"]) - float(last["sps_mass"])
    pe, ap = (float(last[key]) / 1000 for key in ("periapsis", "apoapsis"))
    if not (debit > 0 and math.isfinite(pe) and math.isfinite(ap) and pe < ap):
        raise ValueError(f"{prefix}: invalid cutoff telemetry {last}")
    pad_pe = float(field(pad, "MCC_AP7MNV_HP")) * 1.852
    pad_ap = float(field(pad, "MCC_AP7MNV_HA")) * 1.852
    result = dict(burn=prefix, ignition_get_s=cmc_tig, target_lvlh_ft_s=cmc_dv, sps_used_kg=debit,
                  pad_perigee_km=pad_pe, pad_apogee_km=pad_ap, perigee_km=pe, apogee_km=ap)
    burn_dir = output / (prefix + "-burn")
    saved_pe, saved_ap = saved_orbit(burn_dir)
    if not (abs(saved_pe - 1000 * pe) < 100 and abs(saved_ap - 1000 * ap) < 100):
        raise ValueError(f"{prefix}: saved position and velocity disagree with cutoff telemetry")
    if number < 8:
        if not (abs(pe - pad_pe) < 15 and abs(ap - pad_ap) < 15):
            raise ValueError(f"{prefix}: cutoff orbit missed the maneuver PAD")
        if number == 4:
            receipt, = rows(burn_dir / "burn.csv")
            target = dv[0] * .3048
            achieved = float(receipt["achieved_delta_v_m_s"])
            ullage = float(receipt["ullage_delta_v_m_s"])
            passed = .55 < ullage < 1.9 and .5 * target < achieved < 1.5 * target
            result["delta_v_method"] = "change in orbital energy"
        else:
            receipt, = rows(burn_dir / "burn-result.csv")
            target = math.hypot(*dv) * .3048
            achieved = float(receipt["delivered_m_s"])
            ullage = float(receipt["ullage_m_s"])
            measured = [float(receipt[f"achieved_{axis}_m_s"]) for axis in "xyz"]
            error = math.dist(measured, [component * .3048 for component in dv])
            tolerance = max(2, .03 * target)
            passed = .4 < ullage < 3 and abs(achieved - target) < tolerance and error < tolerance
            result["delta_v_method"] = "rocket equation plus measured ullage"
            result.update(integrated_lvlh_m_s=measured, vector_error_m_s=error)
        if not passed:
            raise ValueError(f"{prefix}: delta-v or ullage fell outside the replay tolerance")
        result.update(target_delta_v_m_s=target, achieved_delta_v_m_s=achieved, ullage_m_s=ullage)
    return result


def verify(output):
    from apollo7_checks import rows
    from apollo7_entry import verify_burn, verify_entry

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
    stages = [item["stage"] for item in records]
    expected = []
    for number in range(4, 9):
        prefix = f"sps{number}-"
        expected.append(prefix + "coast")
        if number == 5 and prefix + "retarget" in stages:
            expected.append(prefix + "retarget")
        expected.extend(prefix + part for part in ("uplink", "p30", "alignment", "prepare-p40", "burn"))
        packets = [r["phase"] for r in rows(output / (prefix + "uplink") / "uplink.csv")]
        required = {"accepted", "csm_state_vector", "second_state_vector", "target_uplink_verified"}
        required.update(("retrofire_target", "entry_reference") if number == 8 else ("external_delta_v",))
        if set(packets) != required or len(packets) != len(required):
            raise ValueError(f"{prefix}uplink: missing or unexpected CMC readbacks")
    expected.extend(("entry-p61", "entry-separation", "entry-attitude", "entry-splashdown", "entry-recovery"))
    if stages != expected:
        raise ValueError(f"Incomplete or out-of-order flight: {stages}")
    verify_burn(output / "sps8-burn", output / "sps8-coast")
    verify_entry(output / "entry-separation", previous)
    splashdown = rows(output / "entry-splashdown" / "deorbit-to-entry.csv")[-1]
    recovery = rows(previous / "recovery.csv")[-1]
    report = dict(start_get=clock(SEED), end_get=clock(previous), seed_sha256=SEED_SHA256,
                  handoffs=len(records), burns=[burn_measurements(output, n) for n in range(4, 9)],
                  splashdown_get_s=float(splashdown["met"]), contact_airspeed_m_s=float(splashdown["airspeed"]),
                  recovery=recovery)
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"{len(records)} linked flights passed from SPS-3 to splashdown at GET {clock(previous):.2f}.")


def main(inputs, output):
    from apollo7_four import fly as sps4
    from apollo7_middle import fly as sps5_through_7
    from apollo7_entry import fly as sps8_and_entry

    if digest(SEED / "saved.scn") != SEED_SHA256:
        raise ValueError("Wrong SPS-3 save")
    chain = Chain(inputs, output)
    build = dict(orbiter_source=(chain.inputs / "orbiter-source.txt").read_text().strip(),
                 nassp_source=os.environ.get("GITHUB_SHA"),
                 engine_sha256=chain.engine_sha, seed_sha256=SEED_SHA256)
    (chain.output / "build.json").write_text(json.dumps(build, indent=2) + "\n")
    previous = SEED
    for fly in (sps4, sps5_through_7, sps8_and_entry):
        previous = fly(chain, previous)
    verify(chain.output)


if __name__ == "__main__":
    if sys.argv[1] == "--verify":
        verify(Path(sys.argv[2]))
    else:
        main(*sys.argv[1:])
