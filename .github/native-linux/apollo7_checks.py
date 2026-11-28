"""SPS-3 must meet the maneuver PAD and continue from its actual flown save."""
import csv
import math
from pathlib import Path


SPS3 = "runtime-release-apollo7-countdown-sps3-scs-burn-rate-mode"
PAD_PERIGEE_M = 175838.224380
PAD_APOGEE_M = 309338.700664
PAD_TOLERANCE_M = 15000


def rows(path):
    with Path(path).open() as stream:
        result = list(csv.DictReader(stream))
    assert result, path
    return result


def check_orbit(perigee, apogee, target=(PAD_PERIGEE_M, PAD_APOGEE_M)):
    assert math.isfinite(perigee) and abs(perigee - target[0]) < PAD_TOLERANCE_M, perigee
    assert math.isfinite(apogee) and abs(apogee - target[1]) < PAD_TOLERANCE_M, apogee


def verify_sps3(run, pad=None, followon=None):
    target = (PAD_PERIGEE_M, PAD_APOGEE_M)
    if pad is not None:
        from apollo7_four import scenario_field
        target = tuple(float(scenario_field(pad,"MCC_AP7MNV_" + key))*1852 for key in ("HP","HA"))
    samples = rows(run / "sps3-scs.csv")
    assert samples[-1]["marker"] == "sps3_completed", samples[-1]
    assert not any(row["marker"] == "sps3_trajectory_needs_correction" for row in samples)
    final = samples[-1]
    check_orbit(float(final["periapsis"]), float(final["apoapsis"]), target)
    used = float(samples[0]["sps_mass"]) - float(final["sps_mass"])
    if pad is None:
        assert 300 < used < 360, used
    else:
        planned = 29.606 * float(scenario_field(pad, "MCC_AP7MNV_burntime"))
        assert abs(used-planned)<max(18,.12*planned), (used,planned)

    telemetry = rows(run / "sps3-qualification.csv")
    events = {row["marker"]: row for row in telemetry}
    begin, end = events["ullage"], events["ullage_complete"]
    duration = float(end["relative_to_tig"]) - float(begin["relative_to_tig"])
    assert 15 <= duration <= 15.3, duration
    impulse = float(end["ullage_impulse_m_s"])
    assert 1 < impulse < 3, impulse  # Reject the old step-dependent weak ullage.
    ignition = events["manual_ignition"]
    for row in (end, ignition):
        assert 0 <= float(row["attitude_error_deg"]) < 2, row
        assert 0 <= float(row["rate_deg_s"]) < .5, row
    assert 0 <= float(ignition["relative_to_tig"]) < .1, ignition
    burning = next(row for row in telemetry if float(row["sps_level"]) > .5)
    assert .9 <= float(burning["relative_to_tig"]) < 1.2, burning
    for name in ("ems_cutoff_check", "sps3_completed"):
        row = events[name]
        assert float(row["ems_fps"]) <= 0 and float(row["sps_level"]) == 0, row

    if followon is None:
        followon = run / "followon"
        saved = (run / "saved.scn").read_text(encoding="latin-1")
        expected_input = saved.replace(
            "  Script ProjectApollo/apollo7-countdown-sps3-scs-burn-rate-mode\n",
            "  Script ProjectApollo/apollo7-sps3-postburn-replay\n",
        )
        assert expected_input != saved
        assert (followon / "input.scn").read_text(encoding="latin-1") == expected_input
    else:
        from apollo7_chain import input_bytes
        assert (followon / "input.scn").read_bytes() == input_bytes(run)
    log = (followon / "console.log").read_text(errors="replace")
    assert "Native OpenGL renderer:" in log and "LuaCall" not in log
    assert "Saved finalized production scenario:" in log
    final_save = (followon / "saved.scn").read_text(encoding="latin-1")
    csm = final_save.split("\nAS-205:", 1)[1].split("\nEND\n", 1)[0]
    assert "STATUS Orbiting Earth\n" in csm and "  STAGE 30\n" in csm

    continuation = rows(followon / "postburn.csv")
    stages = {row["event"]: row for row in continuation}
    initial, complete = stages["reloaded_sps3"], stages["post_sps3_continuation_complete"]
    shutdown = stages["p00_shutdown_complete"]
    elapsed = float(complete["elapsed_s"]) - float(shutdown["elapsed_s"])
    clock_elapsed = float(complete["agc_get_s"]) - float(shutdown["agc_get_s"])
    assert 1800 <= elapsed <= 1803 and abs(clock_elapsed - elapsed) < 2, (elapsed, clock_elapsed)
    assert abs(float(initial["sps_mass"]) - float(final["sps_mass"])) < .005
    for row in continuation:
        assert abs(float(row["sps_mass"]) - float(initial["sps_mass"])) < .005, row
        check_orbit(float(row["periapsis_m"]), float(row["apoapsis_m"]), target)
        if row["event"] in ("p00_shutdown_complete", "post_sps3_coast", "post_sps3_continuation_complete"):
            assert row["program"] == "0", row
    for key, original in (("periapsis_m", "periapsis"), ("apoapsis_m", "apoapsis")):
        # Catch discontinuities at reload. The full mission enables oblate
        # Earth gravity, so osculating apsides evolve during the ensuing coast.
        assert abs(float(initial[key]) - float(final[original])) < 100, (key, initial[key], final[original])
        if pad is None:
            assert abs(float(complete[key]) - float(final[original])) < 100, (key, complete[key], final[original])
    if pad is not None:
        from apollo7_chain import saved_orbit
        for key, value in zip(("periapsis_m", "apoapsis_m"), saved_orbit(followon), strict=True):
            assert abs(value - float(complete[key])) < 100, (key, value, complete[key])
    return {
        "perigee_km": float(final["periapsis"]) / 1000,
        "apogee_km": float(final["apoapsis"]) / 1000,
        "sps_used_kg": used,
        "ullage_impulse_m_s": impulse,
        "ullage_attitude_error_deg": float(end["attitude_error_deg"]),
        "ignition_attitude_error_deg": float(ignition["attitude_error_deg"]),
        "linked_postburn_coast_s": elapsed,
        "postburn_program": int(complete["program"]),
    }
