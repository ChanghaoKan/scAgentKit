#!/bin/sh
set -eu
if [ "$#" -lt 1 ]; then
  printf '%s\n' 'Usage: workbench/run-project.sh /path/to/exported-project [--port 8768] [--project /path/to/second-project]' >&2
  exit 2
fi
PROJECT_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIRECTORY=$1
shift
exec python3 -B "$PROJECT_SCRIPT_DIR/server.py" --project "$PROJECT_DIRECTORY" --port 8768 "$@"
