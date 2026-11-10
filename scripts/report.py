#!/usr/bin/env python3
"""Median and spread per server and endpoint from bench.csv.

Writes results.md (tables) and rps.svg / p99.svg (grouped bars: median of the
rounds, whiskers from the slowest to the fastest round).
"""
import csv
import os
import statistics
import sys

results = sys.argv[1]
rows = list(csv.DictReader(open(os.path.join(results, "bench.csv"))))
servers = list(dict.fromkeys(r["server"] for r in rows))
endpoints = list(dict.fromkeys(r["endpoint"] for r in rows))
NAMES = {"pam": "PAM", "frankenphp": "FrankenPHP", "swoole": "Swoole", "roadrunner": "RoadRunner"}
COLORS = {"light": ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"], "dark": ["#3987e5", "#d95926", "#199e70", "#c98500"]}


def values(server, endpoint, column):
    return [float(r[column]) for r in rows if r["server"] == server and r["endpoint"] == endpoint and r[column] != ""]


def stats(server, endpoint, column):
    v = values(server, endpoint, column)
    return (statistics.median(v), min(v), max(v)) if v else (0.0, 0.0, 0.0)


rounds = len({r["round"] for r in rows})
md = [f"Median of {rounds} rounds; the range is the slowest and the fastest round.\n",
      "### Requests per second\n",
      "| Endpoint | " + " | ".join(NAMES.get(s, s) for s in servers) + " |",
      "|---|" + "---:|" * len(servers)]
for endpoint in endpoints:
    cells = []
    for server in servers:
        median, low, high = stats(server, endpoint, "rps")
        cells.append(f"{median:,.0f} ({low:,.0f} to {high:,.0f})")
    md.append(f"| {endpoint} | " + " | ".join(cells) + " |")

md += ["", "### Latency, p50 / p99 (ms)\n",
       "| Endpoint | " + " | ".join(NAMES.get(s, s) for s in servers) + " |",
       "|---|" + "---:|" * len(servers)]
for endpoint in endpoints:
    cells = []
    for server in servers:
        p50 = stats(server, endpoint, "p50_ms")[0]
        p99, low, high = stats(server, endpoint, "p99_ms")
        cells.append(f"{p50:.2f} / {p99:.2f} ({low:.2f} to {high:.2f})")
    md.append(f"| {endpoint} | " + " | ".join(cells) + " |")

md += ["", "### Errors and memory\n",
       "| Server | Socket errors + non-2xx (all runs) | Container memory after the last endpoint, median (MiB) | Container peak, max (MiB) |",
       "|---|---:|---:|---:|"]
for server in servers:
    mine = [r for r in rows if r["server"] == server]
    errors = sum(int(r["errors"] or 0) for r in mine)
    last = [float(r["memory_current_mib"]) for r in mine if r["endpoint"] == mine[-1]["endpoint"]]
    peak = max(float(r["memory_peak_mib"]) for r in mine)
    md.append(f"| {NAMES.get(server, server)} | {errors} | {statistics.median(last):.0f} | {peak:.0f} |")
md += ["", "Memory is the container's cgroup `memory.current`/`memory.peak` and includes the page cache."]
open(os.path.join(results, "results.md"), "w").write("\n".join(md) + "\n")
print("\n".join(md))


def chart(column, title, unit, filename, decimals=0):
    width, height = 760, 400
    left, right, top, bottom = 70, 20, 70, 50
    plot_w, plot_h = width - left - right, height - top - bottom
    top_value = max(stats(s, e, column)[2] for s in servers for e in endpoints) * 1.08
    step = 10 ** max(0, len(str(int(top_value))) - 1)
    for candidate in (step / 2, step / 4, step / 5):
        if top_value / step < 4:
            step = candidate
    ticks = [i * step for i in range(int(top_value // step) + 1)]
    y = lambda v: top + plot_h - v / top_value * plot_h
    group_w = plot_w / len(endpoints)
    bar_w = min(28, (group_w - 24) / len(servers) - 2)
    css = ["svg{font-family:system-ui,-apple-system,Segoe UI,sans-serif}",
           ".bg{fill:#fcfcfb}.t1{fill:#1f1f1e}.t2{fill:#5f5e5a}.grid{stroke:#e4e3de}.whisker{stroke:#1f1f1e}"]
    css += [f".s{i}{{fill:{c}}}" for i, c in enumerate(COLORS["light"])]
    dark = [".bg{fill:#1a1a19}.t1{fill:#f0efec}.t2{fill:#c3c2b7}.grid{stroke:#34332f}.whisker{stroke:#f0efec}"]
    dark += [f".s{i}{{fill:{c}}}" for i, c in enumerate(COLORS["dark"])]
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" role="img" aria-label="{title}">',
           f"<style>{''.join(css)}@media (prefers-color-scheme: dark){{{''.join(dark)}}}</style>",
           f'<rect class="bg" width="{width}" height="{height}" rx="8"/>',
           f'<text class="t1" x="{left}" y="26" font-size="16" font-weight="600">{title}</text>']
    x = left
    for i, server in enumerate(servers):
        out.append(f'<rect class="s{i}" x="{x}" y="40" width="10" height="10" rx="2"/>'
                   f'<text class="t2" x="{x + 14}" y="49" font-size="12">{NAMES.get(server, server)}</text>')
        x += 14 + 8 * len(NAMES.get(server, server)) + 20
    for tick in ticks:
        label = f"{tick:,.0f}" if decimals == 0 else f"{tick:.{decimals}f}"
        out.append(f'<line class="grid" x1="{left}" x2="{width - right}" y1="{y(tick):.1f}" y2="{y(tick):.1f}" stroke-width="1"/>'
                   f'<text class="t2" x="{left - 8}" y="{y(tick) + 4:.1f}" font-size="11" text-anchor="end">{label}</text>')
    out.append(f'<text class="t2" x="14" y="{top + plot_h / 2}" font-size="11" transform="rotate(-90 14 {top + plot_h / 2})" text-anchor="middle">{unit}</text>')
    for g, endpoint in enumerate(endpoints):
        gx = left + g * group_w + (group_w - len(servers) * (bar_w + 2)) / 2
        for i, server in enumerate(servers):
            median, low, high = stats(server, endpoint, column)
            bx = gx + i * (bar_w + 2)
            h = top + plot_h - y(median)
            r = min(4, h / 2)
            out.append(f'<path class="s{i}" d="M{bx:.1f},{top + plot_h:.1f} V{y(median) + r:.1f} Q{bx:.1f},{y(median):.1f} {bx + r:.1f},{y(median):.1f} '
                       f'H{bx + bar_w - r:.1f} Q{bx + bar_w:.1f},{y(median):.1f} {bx + bar_w:.1f},{y(median) + r:.1f} V{top + plot_h:.1f} Z">'
                       f'<title>{NAMES.get(server, server)}, {endpoint}: {median:,.{decimals}f} {unit} (rounds {low:,.{decimals}f} to {high:,.{decimals}f})</title></path>')
            cx = bx + bar_w / 2
            out.append(f'<line class="whisker" x1="{cx:.1f}" x2="{cx:.1f}" y1="{y(low):.1f}" y2="{y(high):.1f}" stroke-width="1.5"/>')
        out.append(f'<text class="t1" x="{left + g * group_w + group_w / 2:.1f}" y="{top + plot_h + 20}" font-size="12" text-anchor="middle">{endpoint}</text>')
    out.append(f'<text class="t2" x="{width - right}" y="{height - 10}" font-size="10" text-anchor="end">Bar: median of {rounds} rounds. Line: slowest to fastest round.</text>')
    out.append("</svg>")
    open(os.path.join(results, filename), "w").write("\n".join(out) + "\n")


chart("rps", "Requests per second (higher is better)", "requests/s", "rps.svg")
chart("p99_ms", "p99 latency (lower is better)", "ms", "p99.svg", decimals=1)
