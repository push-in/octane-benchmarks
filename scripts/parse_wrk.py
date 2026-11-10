#!/usr/bin/env python3
"""One CSV row from a `wrk --latency` output file."""
import re
import sys

path, round_, server, endpoint, current, peak = sys.argv[1:7]
text = open(path).read()


def latency(label):
    match = re.search(rf"^\s*{label}%\s+([\d.]+)(us|ms|s)\b", text, re.M)
    if not match:
        return ""
    value, unit = float(match.group(1)), match.group(2)
    return round(value / 1000 if unit == "us" else value * 1000 if unit == "s" else value, 3)


rps = re.search(r"Requests/sec:\s+([\d.]+)", text)
errors = sum(int(x) for x in re.findall(r"(?:connect|read|write|timeout) (\d+)", text))
non2xx = re.search(r"Non-2xx or 3xx responses: (\d+)", text)
errors += int(non2xx.group(1)) if non2xx else 0
print(",".join(map(str, [round_, server, endpoint, rps.group(1) if rps else "", latency("50"), latency("99"),
                         errors, current, peak])))
