"""Replay consecutive Apollo 7 crew procedures from the corrected SPS-3 save."""
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
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
        # The CMC and RTCC propagate oblate Earth gravity. Give the host the
        # same model throughout the coast, burn, and atmospheric entry.
        cfg = (self.runtime / "Orbiter.cfg").read_text()
        cfg = re.sub(r"(?im)^\s*NonsphericalGravitySources\s*=.*$", "", cfg)
        self.config = self.output / "Orbiter.cfg"
        self.config.write_text("NonsphericalGravitySources = TRUE\n" + cfg)
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
                "--planets", self.runtime / "planet-archives", "--config", self.config,
                "--xrsound-assets", self.runtime / "resources", "--scenario", "input.scn",
                "--save", "saved.scn", "--replay", "replay.csv", "--ticks", str(ticks),
                "--fixed-step", str(step), "--render-every", "257", "--run"]
        env = os.environ.copy()
        env["NASSP_SYNCHRONOUS_MCC"] = "1"
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


def inertial_reference(directory):
    raw = (directory / "saved.scn").read_text(encoding="latin-1")
    imu = raw.split("\nIMU_BEGIN\n", 1)[1].split("\nIMU_END", 1)[0]
    physical = [float(x) for x in re.findall(r"^  M[123][123] (.+)$", imu, re.M)]
    memory = raw.split("\nAGC_BEGIN\n", 1)[1].split("\nAGC_END", 1)[0]
    words = {int(addr, 8): int(word, 8) for addr, word in
             re.findall(r"^  EMEM([0-7]+) ([0-7]+)$", memory, re.M)}

    # RTCC's MCCCRF_DL is the actual CMC reference at 01735. Each
    # coefficient is a B+1 double-precision one's-complement fraction.
    def signed(addr):
        word = words.get(addr, 0)
        return word - 0o77777 if word & 0o40000 else word

    cmc = [signed(i) / 2**13 + signed(i + 1) / 2**27
           for i in range(0o1735, 0o1735 + 18, 2)]
    # The physical stable-member axes mapped by the AGC matrix into global
    # coordinates should give the same inertial frame after each alignment.
    return [sum(physical[3*i+k] * cmc[3*k+j] for k in range(3))
            for i in range(3) for j in range(3)]


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
    reference = inertial_reference(SEED)
    aligned = inertial_reference(output / (prefix + "-alignment"))
    trace = sum(a*b for a,b in zip(reference, aligned, strict=True))
    if not math.isfinite(trace) or abs(trace - 3) > 2 * (1 - math.cos(math.radians(1))):
        raise ValueError(f"{prefix}: CMC inertial reference disagrees with the physical platform")
    result["platform_error_from_seed_deg"] = math.degrees(math.acos(max(-1, min(1, (trace - 1) / 2))))
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


def recovery_target(output, recovery):
    from apollo7_entry import field

    pad = output / "sps8-coast"
    target_lat = float(field(pad, "RTCC_SplLat"))
    target_lon = float(field(pad, "RTCC_SplLng"))
    if not (-math.pi/2 <= target_lat <= math.pi/2 and -math.pi <= target_lon <= math.pi):
        raise ValueError("Invalid RTCC recovery target")

    basis = inertial_reference(SEED)
    alignment_errors = {}
    for stage in ("sps8-burn", "entry-p61", "entry-separation", "entry-attitude", "entry-splashdown"):
        platform = inertial_reference(output / stage)
        trace = sum(a*b for a, b in zip(basis, platform, strict=True))
        error = math.degrees(math.acos(max(-1, min(1, (trace - 1)/2))))
        if not math.isfinite(trace) or error > 1:
            raise ValueError(f"{stage}: IMU and CMC references disagree by {error:.2f} degrees")
        alignment_errors[stage] = error

    # Colossus LAT(SPL) and LNG(SPL) are DP fractions of one revolution.
    save = (output / "entry-p61/saved.scn").read_text(encoding="latin-1")
    agc = save.split("\nAGC_BEGIN\n", 1)[1].split("\nAGC_END", 1)[0]
    words = {int(a, 8): int(w, 8) for a, w in re.findall(r"^  EMEM([0-7]+) ([0-7]+)$", agc, re.M)}
    def signed(a):
        word = words.get(a, 0)
        return word - 0o77777 if word & 0o40000 else word
    def angle(a):
        return math.tau * (signed(a) / 2**14 + signed(a+1) / 2**28)
    # Recover the target direction as Colossus LALOTORV does for Earth.
    cmc_lat = angle(0o3400)
    cmc_target_lat = math.atan2(0.9933064884 * math.sin(cmc_lat), math.cos(cmc_lat))
    if max(abs(cmc_target_lat - target_lat), abs(angle(0o3402) - target_lon)) > 1e-6:
        raise ValueError("P61 splashdown coordinates disagree with the live retrofire PAD")

    lat, lon = (math.radians(float(recovery[key])) for key in ("latitude", "longitude"))
    hav = math.sin((lat-target_lat)/2)**2 + math.cos(lat)*math.cos(target_lat)*math.sin((lon-target_lon)/2)**2
    miss_nm = 2 * 6371000 * math.asin(math.sqrt(min(1, hav))) / 1852
    if not math.isfinite(miss_nm) or miss_nm > 10:
        raise ValueError(f"Splashdown missed the RTCC recovery target by {miss_nm:.2f} nmi (limit 10 nmi)")
    return dict(latitude_deg=math.degrees(target_lat), longitude_deg=math.degrees(target_lon),
                cmc_geodetic_latitude_deg=math.degrees(cmc_lat), miss_nm=miss_nm, limit_nm=10,
                alignment_error_deg_by_stage=alignment_errors)


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
    if not atlantic_water(output / "coast.vec", float(recovery["longitude"]), float(recovery["latitude"])):
        raise ValueError("The final contact is on land on Orbiter's Earth coastline map")
    target = recovery_target(output, recovery)
    report = dict(start_get=clock(SEED), end_get=clock(previous), seed_sha256=SEED_SHA256,
                  handoffs=len(records), burns=[burn_measurements(output, n) for n in range(4, 9)],
                  splashdown_get_s=float(splashdown["met"]), contact_airspeed_m_s=float(splashdown["airspeed"]),
                  recovery=recovery, recovery_target=target)
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"{len(records)} linked flights passed from SPS-3 to splashdown at GET {clock(previous):.2f}.")


def atlantic_water(coastline, longitude, latitude):
    """Count coastline crossings from open Atlantic water at 40 W, 30 N."""
    if digest(coastline) != "9b33031ebfc88ade6daabd1d3ec6a7ce5d91b61daaf5211bf2cdde9f98bc79b3":
        raise ValueError("Unexpected Orbiter Earth coastline data")
    lines = iter(coastline.read_text().splitlines())
    next(lines)
    segments = int(next(lines).split()[0])
    dx, dy = longitude + 40, latitude - 30
    span2 = dx*dx + dy*dy
    crossings = 0
    for _ in range(segments):
        vertices = [tuple(map(float, next(lines).split())) for _ in range(int(next(lines)))]
        for (x1, y1), (x2, y2) in zip(vertices, vertices[1:]):
            if abs(x1 - x2) > 180:
                continue  # Map seam on the opposite side of the Earth.
            s1 = dx*(y1-30) - dy*(x1+40)
            s2 = dx*(y2-30) - dy*(x2+40)
            if (s1 > 0) == (s2 > 0):
                continue
            t = s1 / (s1-s2)
            along = dx*(x1+40 + t*(x2-x1)) + dy*(y1-30 + t*(y2-y1))
            if 0 < along < span2:
                crossings += 1
    return crossings % 2 == 0


def main(inputs, output):
    from apollo7_four import fly as sps4
    from apollo7_middle import fly as sps5_through_7
    from apollo7_entry import fly as sps8_and_entry

    if digest(SEED / "saved.scn") != SEED_SHA256:
        raise ValueError("Wrong SPS-3 save")
    chain = Chain(inputs, output)
    shutil.copyfile(chain.runtime / "resources/Config/Earth/Data/coast.vec", chain.output / "coast.vec")
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
