Median of 5 rounds; the range is the slowest and the fastest round.

### Requests per second

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 12,187 (11,121 to 12,627) | 11,352 (11,165 to 11,526) | 9,200 (8,829 to 9,353) | 7,498 (7,373 to 7,552) |
| json | 11,409 (10,634 to 12,219) | 10,854 (10,730 to 11,345) | 9,292 (9,105 to 9,403) | 7,319 (7,180 to 7,766) |
| db | 9,880 (9,205 to 10,352) | 9,285 (9,056 to 9,606) | 7,966 (7,833 to 8,018) | 6,139 (5,980 to 6,237) |
| view | 10,271 (9,409 to 10,800) | 9,263 (8,113 to 10,066) | 7,938 (7,865 to 7,958) | 6,602 (6,459 to 6,744) |

### Latency, p50 / p99 (ms)

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 5.19 / 11.37 (6.67 to 12.70) | 5.48 / 10.24 (10.04 to 10.80) | 6.62 / 14.88 (7.66 to 16.79) | 8.41 / 11.67 (10.97 to 11.97) |
| json | 5.36 / 12.26 (6.82 to 13.01) | 5.76 / 10.42 (10.03 to 10.53) | 7.06 / 8.32 (7.52 to 14.49) | 8.64 / 11.95 (11.42 to 12.33) |
| db | 6.32 / 8.88 (7.60 to 15.01) | 6.77 / 11.47 (11.13 to 11.77) | 8.08 / 9.17 (8.74 to 12.71) | 10.27 / 14.11 (13.31 to 14.39) |
| view | 6.01 / 13.12 (7.32 to 14.65) | 6.76 / 11.36 (10.50 to 15.60) | 8.11 / 8.69 (8.63 to 9.14) | 9.53 / 12.93 (12.51 to 13.52) |

### Errors and memory

| Server | Socket errors + non-2xx (all runs) | Container memory after the last endpoint, median (MiB) | Container peak, max (MiB) |
|---|---:|---:|---:|
| PAM | 0 | 453 | 515 |
| FrankenPHP | 0 | 482 | 564 |
| Swoole | 0 | 481 | 517 |
| RoadRunner | 0 | 712 | 752 |

Memory is the container's cgroup `memory.current`/`memory.peak` and includes the page cache.
