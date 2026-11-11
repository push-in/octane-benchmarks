#!/usr/bin/env bash
# Everything, in order: images, app, machine spec, benchmark, post-boot zygote,
# edge page cache, zero-loss reload and recycling, behavior checks. Results go to results/<date>/.
#   ./run.sh                 all stages
#   ./run.sh bench           chosen stages (images provision machine bench zygote page-cache zero-loss behavior)
set -euo pipefail
cd "$(dirname "$0")"
STAGES=("${@:-images provision machine bench zygote page-cache zero-loss behavior}")
read -r -a STAGES <<< "${STAGES[*]}"
for stage in "${STAGES[@]}"; do
    bash "scripts/$stage.sh"
done
