#!/usr/bin/env bash
# dump.sh — dumpLayout → recv ./layout.json
set -uo pipefail
export MSYS_NO_PATHCONV=1
REMOTE=/data/local/tmp/layout.json
hdc shell uitest dumpLayout -p "$REMOTE" >/dev/null 2>&1
hdc file recv "$REMOTE" layout.json >/dev/null 2>&1
[ -s layout.json ] && exit 0 || { echo "dump: layout.json empty" >&2; exit 1; }
