#!/usr/bin/env bash
# log.sh <pid> <pattern> — 抓应用日志并过滤
set -uo pipefail
export MSYS_NO_PATHCONV=1
PID="${1:?usage: log.sh <pid> <pattern>}"
PAT="${2:?usage: log.sh <pid> <pattern>}"
timeout 3 hdc shell hilog 2>/dev/null | grep -E "$PAT" | grep " $PID " || true
