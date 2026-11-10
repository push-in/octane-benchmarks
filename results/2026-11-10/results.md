Median of 5 rounds; the range is the slowest and the fastest round.

### Requests per second

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 9,483 (8,949 to 10,004) | 8,892 (8,768 to 8,957) | 7,230 (6,927 to 7,734) | 6,128 (6,107 to 6,196) |
| json | 8,779 (8,692 to 9,745) | 8,627 (8,535 to 8,672) | 6,915 (6,897 to 7,548) | 5,974 (5,949 to 5,997) |
| db | 8,250 (7,380 to 8,367) | 7,303 (7,242 to 7,339) | 5,934 (5,893 to 6,047) | 5,070 (5,057 to 5,102) |
| view | 7,753 (7,698 to 8,596) | 7,522 (7,435 to 7,543) | 6,242 (5,858 to 6,466) | 5,367 (5,338 to 5,374) |

### Latency, p50 / p99 (ms)

| Endpoint | PAM | FrankenPHP | Swoole | RoadRunner |
|---|---:|---:|---:|---:|
| hello | 6.52 / 13.24 (8.09 to 14.50) | 7.01 / 12.20 (12.17 to 12.32) | 8.60 / 16.71 (10.19 to 19.31) | 10.31 / 13.28 (13.18 to 13.36) |
| json | 6.68 / 14.97 (8.16 to 15.38) | 7.25 / 12.42 (12.34 to 12.59) | 8.48 / 17.56 (10.46 to 19.91) | 10.58 / 13.61 (13.54 to 13.70) |
| db | 7.82 / 9.06 (8.92 to 16.38) | 8.56 / 13.55 (13.52 to 13.71) | 9.72 / 21.97 (21.60 to 23.79) | 12.44 / 16.01 (15.87 to 16.07) |
| view | 7.55 / 16.78 (8.82 to 18.09) | 8.33 / 13.19 (13.14 to 13.22) | 10.19 / 16.85 (12.10 to 21.54) | 11.76 / 14.98 (14.90 to 15.05) |

### Errors and memory

| Server | Socket errors + non-2xx (all runs) | Container memory after the last endpoint, median (MiB) | Container peak, max (MiB) |
|---|---:|---:|---:|
| PAM | 0 | 390 | 401 |
| FrankenPHP | 0 | 434 | 517 |
| Swoole | 0 | 435 | 473 |
| RoadRunner | 0 | 686 | 723 |

Memory is the container's cgroup `memory.current`/`memory.peak` and includes the page cache.
