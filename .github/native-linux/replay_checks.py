import csv
import math


def rows(run, filename):
    with (run / filename).open() as stream:
        result = list(csv.DictReader(stream))
    assert result, run / filename
    return result


def vessel(run, name):
    scenario = (run / "saved.scn").read_text(encoding="latin-1")
    section = scenario.split(f"\n{name}:", 1)[1].split("\nEND\n", 1)[0]
    fields = {}
    for line in section.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            fields.setdefault(*parts)
    return fields


def near(actual, expected, tolerance):
    actual = float(actual)
    assert math.isclose(actual, expected, rel_tol=0, abs_tol=tolerance), (actual, expected, tolerance)
    return actual


def docked(run, first, second):
    assert vessel(run, first)["DOCKINFO"] == f"0:0,{second}"
    assert vessel(run, second)["DOCKINFO"] == f"0:0,{first}"
    return {"docked": [first, second]}


def apollo5_insertion(run):
    final = rows(run, "insertion.csv")[-1]
    assert final["lm_dock"] == "true" and final["first_stage_dock"] == "false", final
    return {
        "perigee_km": near(final["perigee_km"], 166.09, 1),
        "apogee_km": near(final["apogee_km"], 240.30, 1),
    }


def apollo5_first_dps(run):
    samples = rows(run, "lm-flight.csv")
    engine = [float(row["dps_or_aps"]) for row in samples]
    peak = near(max(engine), 0.08333, 0.001)
    assert engine[0] == engine[-1] == 0 and samples[-1]["docked_to_ivb"] == "false"
    assert any(row["prog"] == "41" for row in samples)
    return {"peak_dps_throttle": peak}


def apollo5_alternate(run):
    samples = rows(run, "alternate.csv")
    stages = {row["event"] for row in samples}
    assert {"dps2_full", "dps3_ignition", "abort_stage", "aps1_burn", "aps1_cutoff"} <= stages
    assert vessel(run, "LM-1")["CONFIGURATION"] == "2"
    assert "STATUS" in vessel(run, "LM-1-DESCENTSTG")
    assert float(samples[-1]["throttle"]) == 0
    return {"events": list(dict.fromkeys(row["event"] for row in samples))}


def apollo5_aps2(run):
    samples = rows(run, "aps2.csv")
    assert {"manual_start", "burn", "depletion", "after_depletion"} <= {row["event"] for row in samples}
    final = samples[-1]
    assert float(final["aps_propellant_kg"]) == float(final["throttle"]) == 0
    return {"earth_speed_m_s": near(final["earth_speed_m_s"], 9686.94, 10), "remaining_aps_kg": 0}


def apollo10_mcc2(run):
    impulse = rows(run, "sps-impulse.csv")[-1]
    return {
        "along_target_m_s": near(impulse["along_target_m_s"], 13.96, 0.25),
        "lateral_m_s": near(impulse["lateral_m_s"], 0.31, 0.25),
    }


def apollo10_lowpass(run):
    samples = rows(run, "moon-state.csv")
    radii = [math.hypot(*(float(row[key]) for key in ("rx", "ry", "rz"))) for row in samples]
    perilune = near(min(radii) / 1000, 1756.08, 1)
    assert radii[0] > min(radii) and radii[-1] > min(radii)
    return {"minimum_moon_radius_km": perilune}


def apollo10_entry(run):
    samples = rows(run, "capsule-entry.csv")
    interface = next(row for row in samples if row["event"] == "entry-interface")
    contact = next(row for row in samples if row["event"] == "ground-contact")
    last_airborne = samples[samples.index(contact) - 1]
    capsule = vessel(run, "Charlie-Brown")
    assert capsule["STATUS"] == "Landed Earth" and capsule["STAGE"] == "46"
    assert last_airborne["ground_contact"] == "false" and contact["ground_contact"] == "true"
    assert contact["drogue"] == contact["mains_attached"] == "true"
    fpa = math.degrees(math.asin(float(interface["vertical_m_s"]) / float(interface["earth_speed_m_s"])))
    return {
        "entry_angle_deg": near(fpa, -6.46, 0.08),
        "peak_g": near(max(float(row["g_load"]) for row in samples if row["ground_contact"] == "false"), 7.85, 0.5),
        "last_airborne_m_s": near(last_airborne["airspeed_m_s"], 8.80, 0.25),
        "latitude_deg": near(contact["lat_deg"], -15.29, 0.1),
        "longitude_deg": near(contact["lng_deg"], -163.10, 0.1),
    }


def apollo11_tli(run):
    columbia = vessel(run, "Columbia")
    assert columbia["STATUS"] == "Orbiting Earth" and columbia["STAGE"] == "21"
    return {
        "earth_radius_km": near(math.hypot(*map(float, columbia["RPOS"].split())) / 1000, 8490, 100),
        "earth_speed_m_s": near(math.hypot(*map(float, columbia["RVEL"].split())), 9346, 100),
    }


def apollo11_landing(run):
    eagle = vessel(run, "Eagle")
    assert eagle["STATUS"] == "Landed Moon"
    longitude, latitude = map(float, eagle["POS"].split())
    descent = rows(run, "descent.csv")
    assert descent[0]["ground_contact"] == "false" and descent[-1]["ground_contact"] == "true"
    return {
        "touchdown_time_s": near(next(row["elapsed_seconds"] for row in descent if row["ground_contact"] == "true"), 796, 12),
        "longitude_deg": near(longitude, 24.4170, 0.05),
        "latitude_deg": near(latitude, 0.6842, 0.05),
    }


def apollo11_ascent(run):
    eagle = vessel(run, "Eagle")
    assert eagle["STATUS"] == "Orbiting Moon" and eagle["CONFIGURATION"] == "2"
    samples = rows(run, "ascent.csv")
    assert {"staging", "powered", "after-cutoff"} <= {row["event"] for row in samples}
    final = samples[-1]
    assert float(final["aps_throttle"]) == 0
    return {
        "perilune_km": near(float(final["peri_m"]) / 1000, 9.67, 1),
        "apolune_km": near(float(final["apo_m"]) / 1000, 97.52, 2),
    }


def apollo11_p40(run, solution_file, ignition_key, dv_keys, telemetry, delta_v):
    solution = rows(run, solution_file)[-1]
    readbacks = {row["event"]: row for row in rows(run, "agc-verification.csv")}
    tig = readbacks["N33-TIG"]
    hours, minutes, hundredths = (int(tig[key]) for key in ("r1", "r2", "r3"))
    ignition = near(hours * 3600 + minutes * 60 + hundredths / 100, float(solution[ignition_key]), 0.03)
    target = readbacks["N81-delta-v"]
    components = [
        near(int(target[key]) * 0.03048, float(solution[component]), 0.07)
        for key, component in zip(("r1", "r2", "r3"), dv_keys)
    ]
    assert readbacks["authorize-SPS"]["program"] == "40"
    cutoff = rows(run, telemetry)[-1]
    assert cutoff["event"] == "SPS-cutoff"
    return {
        "agc_ignition_get_s": ignition,
        "agc_delta_v_m_s": components,
        "delivered_delta_v_m_s": near(cutoff["dv_total_m_s"], delta_v, 0.6),
    }


def apollo11_tei(run):
    return apollo11_p40(run, "tei-solution.csv", "ignition_get", ("dv_x", "dv_y", "dv_z"), "p40-burn.csv", 977.09)


def apollo11_midcourse(run):
    return apollo11_p40(run, "rtcc-corridor-target.csv", "tig", ("dvx", "dvy", "dvz"), "mcc-burn.csv", 11.33)


def apollo11_entry(run):
    columbia = vessel(run, "Columbia")
    assert columbia["STATUS"] == "Orbiting Earth" and columbia["STAGE"] == "46"
    events = {row["event"]: row for row in rows(run, "guided-entry.csv")}
    assert {"service-module-confirmed", "mode-61", "mode-62", "mode-63", "mode-64", "mode-67",
            "drogue-deploy", "main-deploy"} <= events.keys()
    return {"entry_angle_deg": near(events["entry-interface"]["fpa_deg"], -6.48, 0.15)}


def apollo11_splashdown(run):
    columbia = vessel(run, "Columbia")
    assert columbia["STATUS"] == "Landed Earth" and columbia["STAGE"] == "47"
    contact = rows(run, "splashdown.csv")[-1]
    assert contact["event"] == "splashdown" and contact["ground_contact"] == contact["main_attached"] == "true"
    return {"splashdown_speed_m_s": near(contact["groundspeed_m_s"], 8.31, 0.3)}


CHECKS = {
    "apollo5-insertion": apollo5_insertion,
    "apollo5-first-dps": apollo5_first_dps,
    "apollo5-alternate": apollo5_alternate,
    "apollo5-aps2-crossfeed": apollo5_aps2,
    "apollo10-mcc2": apollo10_mcc2,
    "apollo10-lowpass": apollo10_lowpass,
    "apollo10-docking": lambda run: docked(run, "Charlie-Brown", "Snoopy"),
    "apollo10-entry-250ms": apollo10_entry,
    "apollo10-entry-62p5ms": apollo10_entry,
    "apollo11-tli": apollo11_tli,
    "apollo11-landing": apollo11_landing,
    "apollo11-ascent": apollo11_ascent,
    "apollo11-docking": lambda run: docked(run, "Columbia", "Eagle"),
    "apollo11-tei": apollo11_tei,
    "apollo11-midcourse": apollo11_midcourse,
    "apollo11-entry": apollo11_entry,
    "apollo11-splashdown": apollo11_splashdown,
}


def verify_mission_replays(flight, cases):
    replays = {case: CHECKS[case](flight / case) for case in cases}
    if "apollo10-entry-250ms" in replays:
        first = "apollo10-entry-250ms"
        second = "apollo10-entry-62p5ms"
        assert (flight / first / "input.scn").read_bytes() == (flight / second / "input.scn").read_bytes()
        for key in ("entry_angle_deg", "latitude_deg", "longitude_deg"):
            near(replays[first][key], replays[second][key], 0.05)
    return replays
