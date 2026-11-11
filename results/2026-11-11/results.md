Median of 5 rounds; the range is the slowest and the fastest round.

### Requests per second

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 11,191 (9,820 to 11,709) | 9,826 (8,990 to 10,373) | 8,310 (8,003 to 8,598) | 6,323 (6,182 to 6,521) |
| json | 10,530 (9,451 to 11,034) | 9,479 (9,268 to 9,657) | 8,161 (7,985 to 8,630) | 6,140 (6,014 to 6,368) |
| db | 8,854 (8,425 to 9,199) | 8,260 (7,799 to 8,546) | 7,003 (6,869 to 7,467) | 5,205 (4,985 to 5,417) |
| view | 9,456 (9,375 to 9,888) | 8,329 (7,971 to 8,710) | 6,963 (6,904 to 7,358) | 5,443 (5,201 to 5,634) |

### Latency, p50 / p99 (ms)

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 5.67 / 7.68 (7.46 to 13.94) | 6.32 / 11.52 (10.75 to 12.37) | 7.59 / 9.52 (8.34 to 17.32) | 9.96 / 13.60 (12.96 to 13.76) |
| json | 5.81 / 8.04 (7.83 to 14.22) | 6.58 / 11.88 (11.53 to 12.20) | 7.76 / 8.77 (8.30 to 13.93) | 10.27 / 13.92 (13.54 to 14.37) |
| db | 6.93 / 14.48 (9.02 to 16.39) | 7.58 / 12.77 (12.22 to 13.36) | 9.17 / 10.27 (9.90 to 12.31) | 12.17 / 16.17 (15.91 to 16.91) |
| view | 6.67 / 8.55 (8.16 to 8.73) | 7.54 / 12.43 (11.81 to 14.47) | 9.24 / 10.64 (9.67 to 11.18) | 11.59 / 15.50 (14.53 to 16.04) |

### Errors and memory

| Server | Socket errors + non-2xx (all runs) | Container memory after the last endpoint, median (MiB) | Container peak, max (MiB) |
|---|---:|---:|---:|
| PAM | 0 | 462 | 488 |
| FrankenPHP | 0 | 474 | 540 |
| Swoole | 0 | 463 | 494 |
| RoadRunner | 0 | 719 | 748 |

Memory is the container's cgroup `memory.current`/`memory.peak` and includes the page cache.
