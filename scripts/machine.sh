#!/usr/bin/env bash
# Writes machine.json: CPU, kernel, governor, memory, Docker, wrk, images, load.
source "$(dirname "$0")/lib.sh"
python3 - "$RESULTS/machine.json" "${1:-start}" <<'PY'
import json, platform, subprocess, sys
def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20,
                              env={"LC_ALL": "C", "PATH": "/usr/bin:/bin:/usr/local/bin"}).stdout.strip()
    except Exception as error:
        return str(error)
path, phase = sys.argv[1], sys.argv[2]
if phase == "end":
    data = json.load(open(path))
    data["load_average_at_end"] = sh("cat /proc/loadavg")
    data["governor_at_end"] = sh("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    data["date_end"] = sh("date -u +%Y-%m-%dT%H:%M:%SZ")
    json.dump(data, open(path, "w"), indent=2)
    sys.exit(0)
json.dump({
    "date": sh("date -u +%Y-%m-%dT%H:%M:%SZ"),
    "kernel": platform.release(),
    "cpu": sh("lscpu | sed -n 's/^Model name:\\s*//p'"),
    "threads": sh("nproc"),
    "cpu_max_mhz": sh("lscpu -e=CPU,MAXMHZ | tail -n +2 | tr -s ' ' | tr '\\n' ';'"),
    "memory": sh("free -h | awk '/Mem:/{print $2}'"),
    "governor": sh("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
    "energy_performance_preference": sh("cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"),
    "load_average_at_start": sh("cat /proc/loadavg"),
    "docker": sh("docker version --format '{{.Server.Version}}'"),
    "wrk": sh("wrk --version 2>&1 | head -1"),
    "images": sh("docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep '^octane-bench/'"),
    "tcp_migrate_req_host": sh("cat /proc/sys/net/ipv4/tcp_migrate_req"),
    "other_containers": sh("docker ps --format '{{.Names}}' | grep -v '^bench-' | tr '\\n' ' '"),
}, open(path, "w"), indent=2)
PY
cat "$RESULTS/machine.json"
