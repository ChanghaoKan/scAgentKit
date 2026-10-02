#!/bin/sh
set -eu
if [ "$#" -lt 1 ]; then
  printf '%s\n' 'Usage: workbench/run-local.sh /path/to/frozen/phase1/results [--port 8765] [--session /path/to/session.json]' >&2
  exit 2
fi
WORKBENCH_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKBENCH_RESULTS_ROOT=$1
shift
exec python3 "$WORKBENCH_SCRIPT_DIR/server.py" --results-root "$WORKBENCH_RESULTS_ROOT" "$@"
