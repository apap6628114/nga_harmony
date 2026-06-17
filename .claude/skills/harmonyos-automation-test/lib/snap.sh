#!/usr/bin/env bash
# snap.sh — snapshot → recv ./<name>.jpeg
set -uo pipefail
export MSYS_NO_PATHCONV=1
NAME="${1:-shot}"
REMOTE=/data/local/tmp/"$NAME".jpeg
hdc shell snapshot_display -f "$REMOTE" >/dev/null 2>&1
hdc file recv "$REMOTE" "$NAME".jpeg >/dev/null 2>&1
[ -s "$NAME".jpeg ] && { echo "$NAME.jpeg"; exit 0; } || { echo "snap: fail" >&2; exit 1; }
