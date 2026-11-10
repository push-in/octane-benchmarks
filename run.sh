#!/usr/bin/env bash
# Everything, in order: images, app, machine spec, benchmark, zero-loss reload,
# behavior checks. Results go to results/<date>/.
#   ./run.sh                 all stages
#   ./run.sh bench           chosen stages (images provision machine bench zero-loss behavior)
set -euo pipefail
cd "$(dirname "$0")"
STAGES=("${@:-images provision machine bench zero-loss behavior}")
read -r -a STAGES <<< "${STAGES[*]}"
for stage in "${STAGES[@]}"; do
    bash "scripts/$stage.sh"
done
