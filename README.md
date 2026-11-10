# Laravel Octane server benchmark

A reproducible comparison of the four Laravel Octane servers (PAM, FrankenPHP,
Swoole and RoadRunner) serving **the same Laravel application**, plus the
evidence behind the proposal to add PAM to Octane
([push-in/octane, branch `2.x-pam`](https://github.com/push-in/octane/tree/2.x-pam)):

1. Octane's own test suite with the PAM integration.
2. Throughput and latency of the four servers.
3. Zero-loss reload under load.
4. Request timeout (504) and upload memory.

Every number below links to the raw output it comes from. They are valid only
relative to each other, on the machine described in
[`machine.json`](results/2026-11-10/machine.json). Please run it on your own
hardware.

## Results (2026-11-10)

### Octane's test suite

Octane `2.x` with the PAM integration, commit
[`94a5ae5`](https://github.com/push-in/octane/commit/94a5ae57382a732f56ab90e107dc1b8c0146ea1f).

| Run | Tests | Pass | Fail | Skipped |
|---|---:|---:|---:|---:|
| [On PAM's PHP 8.5.12](results/2026-11-09/octane-suite/upstream.txt) | 238 | 195 | 0 | 43 (Swoole-only: no `swoole` extension) |
| [Same suite, every request and response through `PamClient`](results/2026-11-09/octane-suite/pam-driver.txt) | 238 | 195 | 0 | 43 |
| [PHP 8.5.12 CLI with Swoole 6.2.3](results/2026-11-09/octane-suite/php85-cli-swoole.txt) | 238 | 238 | 0 | 0 |

In the second run, [`PamFakeClient`](readiness/octane-suite/adapter/PamFakeClient.php)
replaces Octane's `FakeClient`: each of the 112 request/response exchanges of
the suite also goes through `Laravel\Octane\Pam\PamClient`, and the status,
body and cookies it writes are compared with what Laravel produced:
[0 mismatches](results/2026-11-09/octane-suite/pam-crosscheck.json).
Per-test results: [summary.md](results/2026-11-09/octane-suite/summary.md).

### Throughput and latency

![Requests per second](results/2026-11-10/rps.svg)

![p99 latency](results/2026-11-10/p99.svg)

Median of 5 rounds; in parentheses, the slowest and the fastest round
([results.md](results/2026-11-10/results.md), [bench.csv](results/2026-11-10/bench.csv),
[raw `wrk` output](results/2026-11-10/raw)).

Requests per second:

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 9,483 (8,949 to 10,004) | 8,892 (8,768 to 8,957) | 7,230 (6,927 to 7,734) | 6,128 (6,107 to 6,196) |
| json | 8,779 (8,692 to 9,745) | 8,627 (8,535 to 8,672) | 6,915 (6,897 to 7,548) | 5,974 (5,949 to 5,997) |
| db | 8,250 (7,380 to 8,367) | 7,303 (7,242 to 7,339) | 5,934 (5,893 to 6,047) | 5,070 (5,057 to 5,102) |
| view | 7,753 (7,698 to 8,596) | 7,522 (7,435 to 7,543) | 6,242 (5,858 to 6,466) | 5,367 (5,338 to 5,374) |

Latency p50 / p99 in ms (p99 range in parentheses):

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 6.52 / 13.24 (8.09 to 14.50) | 7.01 / 12.20 (12.17 to 12.32) | 8.60 / 16.71 (10.19 to 19.31) | 10.31 / 13.28 (13.18 to 13.36) |
| json | 6.68 / 14.97 (8.16 to 15.38) | 7.25 / 12.42 (12.34 to 12.59) | 8.48 / 17.56 (10.46 to 19.91) | 10.58 / 13.61 (13.54 to 13.70) |
| db | 7.82 / 9.06 (8.92 to 16.38) | 8.56 / 13.55 (13.52 to 13.71) | 9.72 / 21.97 (21.60 to 23.79) | 12.44 / 16.01 (15.87 to 16.07) |
| view | 7.55 / 16.78 (8.82 to 18.09) | 8.33 / 13.19 (13.14 to 13.22) | 10.19 / 16.85 (12.10 to 21.54) | 11.76 / 14.98 (14.90 to 15.05) |

| Server | Errors (all runs) | Container memory after the run, median (MiB) | Container peak (MiB) |
|---|---:|---:|---:|
| PAM | 0 | 390 | 401 |
| FrankenPHP | 0 | 434 | 517 |
| Swoole | 0 | 435 | 473 |
| RoadRunner | 0 | 686 | 723 |

Reading these numbers:

- PAM has the highest median throughput on every endpoint: 1.8 % (json) to 13 %
  (db) above FrankenPHP, 24 to 39 % above Swoole and 44 to 63 % above RoadRunner.
- FrankenPHP has a lower and steadier p99 than PAM on `hello`, `json` and
  `view`; PAM's p99 also varies more between rounds.
- Memory is the cgroup's `memory.current` / `memory.peak` and includes the page cache.

### Zero-loss reload

`octane:start --server=pam --workers=4 --max-requests=2000`, `wrk -t4 -c64 -d60s`
on `/_r/hello`, and `octane:reload --server=pam` every 4 seconds (13 reloads per
run, none failed), in the PAM container's own network namespace
([zero-loss.csv](results/2026-11-10/zero-loss/zero-loss.csv)).

| `net.ipv4.tcp_migrate_req` | Connections | Requests | Failed |
|---|---|---:|---:|
| 1 (recommended) | keep-alive | [416,219](results/2026-11-10/zero-loss/migrate-1-keep-alive.txt) | 0 |
| 1 (recommended) | new connection per request | [413,337](results/2026-11-10/zero-loss/migrate-1-close.txt) | 0 |
| 0 (kernel default) | keep-alive | [418,317](results/2026-11-10/zero-loss/migrate-0-keep-alive.txt) | 0 |
| 0 (kernel default) | new connection per request | [415,427](results/2026-11-10/zero-loss/migrate-0-close.txt) | 2 (socket write errors) |

PAM reloads make-before-break: the new workers boot before the old ones drain.
Workers share the port with `SO_REUSEPORT`; with the kernel default, Linux
resets a connection whose handshake completes on a listener in the instant it
closes. `tcp_migrate_req=1` (Linux 5.14+) moves it to another listener instead.

### Request timeout and uploads

[behavior.txt](results/2026-11-10/behavior/behavior.txt), PAM container, 2 workers,
PHP `memory_limit=128M`:

- A handler sleeping 6 s with `octane.max_execution_time=2` gets
  `504 Gateway Timeout` after 2.10 s; the worker is replaced and the next 20
  requests return 200.
- A 100 MB and a 1 GB multipart upload: SHA-256 verified before and after
  `UploadedFile::move()`, PHP peak memory 12 MiB, worker peak RSS 64 and 66 MiB,
  no temporary file left behind. PAM streams multipart bodies to
  `upload_tmp_dir` and enforces `upload_max_filesize` / `post_max_size`.

## Method

- **Same app.** `laravel/laravel` with Laravel 13.40.0, Octane from
  `push-in/octane` at a fixed commit (also used for FrankenPHP, Swoole and
  RoadRunner), the routes in [`app/routes/bench.php`](app/routes/bench.php):
  `hello` (string), `json`, `db` (one SQLite row by random primary key out of
  100), `view` (Blade, 20 items). `APP_ENV=production`, `APP_DEBUG=false`,
  `artisan optimize`, the routes without the web middleware group.
- **Same start command.** Every server is started with
  `artisan octane:start --server=<server> --workers=8 --max-requests=10000000`
  ([`scripts/bench.sh`](scripts/bench.sh)); Swoole adds `--task-workers=1`.
- **Same PHP.** PHP 8.5.12 everywhere with [`docker/bench.ini`](docker/bench.ini):
  OPcache with JIT `tracing`, 128 MiB JIT buffer, no timestamp validation,
  `memory_limit=512M`.
- **Pinned versions.** [`versions.env`](versions.env): PAM 2.2.13 (official
  release, checksum verified by its installer), FrankenPHP 1.13.5 (static
  binary), `php:8.5.12-cli-bookworm` with Swoole 6.2.3 and RoadRunner
  2025.1.15, Composer 2.9.3. Dockerfiles in [`docker/`](docker).
- **Pinned CPUs.** The server container runs on CPUs 0-7 (four performance
  cores with SMT), `wrk -t4 -c64` on CPUs 8-11 (two other performance cores),
  `--network host`, one server at a time.
- **Rounds.** 5 rounds; each round runs every server, the order rotating per
  round. For each endpoint: 5 s warmup, then 15 s measured with `--latency`.
- **Machine.** Intel Core Ultra 9 185H laptop, 30 GiB RAM, Linux 7.0.11,
  Docker 28.1.1. The CPU governor was `powersave` (`energy_performance_preference`
  `balance_performance`): setting `performance` needs root
  (`sudo cpupower frequency-set -g performance`), which this run did not have.
  CPU pinning and rotating rounds limit the effect; the spread is reported.
  The run started only after the 1-minute load average stayed below 2 for
  5 minutes; [`load.csv`](results/2026-11-10/load.csv) has the load before each
  server run (about 10 during the run is the benchmark itself: 8 workers plus
  4 `wrk` threads).

## Run it

Requirements: Linux, Docker, `wrk`, `taskset`, Python 3, bash. Root is not
required; for stable numbers set the CPU governor to `performance` first.

```bash
./run.sh                                   # images, app, machine.json, bench, zero-loss, behavior
./run.sh bench                             # one stage
ROUNDS=3 DURATION=30s ./run.sh bench       # any value of versions.env can be overridden
bash readiness/octane-suite/run.sh         # Octane's suite through PamClient (needs pam on PATH)
```

Results are written to `results/<date>/`. Adjust `SERVER_CPUS`, `LOAD_CPUS` and
`WORKERS` to your CPU topology.

## Related

- Octane integration: [push-in/octane `2.x-pam`](https://github.com/push-in/octane/tree/2.x-pam)
  ([diff against laravel/octane `2.x`](https://github.com/laravel/octane/compare/2.x...push-in:octane:2.x-pam))
- Docs: [push-in/docs `13.x-pam`](https://github.com/laravel/docs/compare/13.x...push-in:docs:13.x-pam)
- PAM: [push-in/pam](https://github.com/push-in/pam). Composer bridge for
  current Octane releases: [pushinbr/pam-octane](https://github.com/push-in/pam-octane).

## License

MIT
