import csv
import json
import math
from pathlib import Path


EXPECTATIONS = json.loads(Path(__file__).with_name("mission_expectations.json").read_text())


def verify_replay(run):
    expected = EXPECTATIONS[run.name]
    scenario = (run / "saved.scn").read_text(encoding="latin-1")
    for name, fields in expected["vessels"].items():
        block = scenario.split(f"\n{name}:", 1)[1].split("\nEND\n", 1)[0]
        actual = {}
        for line in block.splitlines():
            parts = line.split(maxsplit=1)
            if len(parts) == 2:
                actual.setdefault(*parts)
        for key, value in fields.items():
            assert actual.get(key) == value, (run.name, name, key, actual.get(key), value)

    results = {}
    for filename, checks in expected["telemetry"].items():
        with (run / filename).open() as stream:
            samples = list(csv.DictReader(stream))
        assert samples, (run.name, filename)
        if "events" in checks:
            column = checks["event_column"]
            actual_events = {row[column] for row in samples}
            assert set(checks["events"]) <= actual_events, (run.name, filename, actual_events)
        final = samples[-1]
        measurements = {}
        for column, rule in checks["last"].items():
            if "equals" in rule:
                assert final[column] == rule["equals"], (run.name, filename, column, final[column], rule)
                measurements[column] = final[column]
            else:
                value = float(final[column])
                assert math.isfinite(value) and math.isclose(
                    value, rule["value"], rel_tol=rule["relative"], abs_tol=rule["absolute"]
                ), (run.name, filename, column, value, rule)
                measurements[column] = value
        results[filename] = measurements
    return results
