#!/usr/bin/env python3
"""Measures a PAM cluster started with an admin address (scripts/zygote.sh).

  zygote_measure.py --admin 127.0.0.1:PORT --workers N --state-dir DIR
                    --respawns K --reloads K --started-at EPOCH_MS

Cold start (start command to every worker ready), spawn to ready per worker
(PAM's worker state records), respawn after SIGKILL of one worker, and reload
(SIGHUP to the master until the next generation has every worker ready).
Prints one JSON object.
"""
import argparse, glob, json, os, signal, statistics, time, urllib.request

p = argparse.ArgumentParser()
p.add_argument("--admin", required=True)
p.add_argument("--workers", type=int, required=True)
p.add_argument("--state-dir", required=True)
p.add_argument("--respawns", type=int, default=5)
p.add_argument("--reloads", type=int, default=5)
p.add_argument("--started-at", type=float, required=True)
a = p.parse_args()


def ready():
    try:
        with urllib.request.urlopen(f"http://{a.admin}/ready", timeout=2) as response:
            return json.loads(response.read())
    except Exception:
        return None


def wait(predicate, limit=120):
    start = time.monotonic()
    while time.monotonic() - start < limit:
        state = ready()
        if state and predicate(state):
            return state
        time.sleep(0.002)
    raise SystemExit("timeout waiting for the cluster")


def all_ready(state, generation=None):
    return (state.get("healthy") and state.get("readyWorkers") == a.workers
            and (generation is None or state.get("generation") == generation))


def summary(values):
    values = sorted(values)
    return {"n": len(values), "min": values[0], "p50": statistics.median(values), "max": values[-1]} if values else None


state = wait(all_ready)
result = {"workers": a.workers, "cold_start_ms": round(time.time() * 1000 - a.started_at)}

respawns = []
for _ in range(a.respawns):
    time.sleep(1.0)
    before = wait(all_ready)
    victim = before["workers"][0]["pid"]
    start = time.monotonic()
    os.kill(victim, signal.SIGKILL)
    wait(lambda s: all_ready(s) and victim not in [w["pid"] for w in s["workers"]])
    respawns.append(round((time.monotonic() - start) * 1000, 1))
result["respawn_after_sigkill_ms"] = summary(respawns)

reloads = []
master = None
for path in glob.glob(os.path.join(a.state_dir, "pam-master-*")):
    master = int(os.path.basename(path).split("-")[2])
for _ in range(a.reloads):
    time.sleep(1.0)
    generation = wait(all_ready)["generation"]
    start = time.monotonic()
    os.kill(master, signal.SIGHUP)
    wait(lambda s: all_ready(s, generation + 1))
    reloads.append(round((time.monotonic() - start) * 1000))
result["reload_ms"] = summary(reloads)

records = []
for path in glob.glob(os.path.join(a.state_dir, "pam-master-*", "worker-*.json")):
    try:
        records.append(json.load(open(path)))
    except (OSError, ValueError):
        pass
spawn = [r["startedAtMillis"] - r["spawnedAtMillis"] for r in records if r.get("startedAtMillis")]
result["spawn_to_ready_ms"] = summary(spawn)
print(json.dumps(result))
