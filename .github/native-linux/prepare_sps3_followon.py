"""Change only the replay script when reloading the newly flown SPS-3 save."""
import re
import sys
from pathlib import Path


def prepare(saved, output):
    raw = Path(saved).read_text(encoding="latin-1")
    raw, count = re.subn(
        r"(?m)^(  Script ProjectApollo/)apollo7-countdown-sps3-scs-burn-rate-mode$",
        r"\1apollo7-sps3-postburn-replay", raw,
    )
    assert count == 1 and "END_SHIPS" in raw
    output = Path(output)
    output.mkdir()
    (output / "input.scn").write_text(raw, encoding="latin-1")
    (output / "replay.csv").write_text("tick,phase,action,value\n")


if __name__ == "__main__":
    prepare(*sys.argv[1:])
