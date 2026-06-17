#!/usr/bin/env bash
# device.sh — 模拟器生命周期 / install / start-app / pid / 就绪
set -uo pipefail
: "${DEVECO_SDK_HOME:=C:/Program Files/Huawei/DevEco Studio/sdk}"
EMU="/c/Program Files/Huawei/DevEco Studio/tools/emulator/Emulator.exe"
export MSYS_NO_PATHCONV=1

cmd="${1:-}"
case "$cmd" in
  emu-start)
    NAME="${2:?usage: emu-start <name>}"
    ( "$EMU" -start "$NAME" >/tmp/emu-"$NAME".log 2>&1 & )
    for _ in $(seq 1 40); do
      sleep 2
      T="$(hdc list targets 2>/dev/null | tr -d '\r\n')"
      if [ "$T" != "[Empty]" ] && [ -n "$T" ]; then
        for _ in $(seq 1 15); do
          [ "$(hdc shell 'param get const.product.model' 2>/dev/null | tr -d '\r\n ')" = "emulator" ] && { echo READY; exit 0; }
          sleep 2
        done
      fi
    done
    echo "emu-start: TIMEOUT" >&2; exit 1
    ;;
  emu-stop)
    "$EMU" -stop "${2:?usage: emu-stop <name>}"; echo OK; exit 0
    ;;
  install)
    HAP="${2:?usage: install <hap>}"
    hdc install -r "$HAP" 2>&1 | tr -d '\r' | grep -q "successfully" && { echo OK; exit 0; } || { echo FAIL; exit 1; }
    ;;
  start-app)
    BUNDLE="${2:?usage: start-app <bundle> <ability>}"
    ABILITY="${3:?usage: start-app <bundle> <ability>}"
    hdc shell aa start -a "$ABILITY" -b "$BUNDLE" 2>&1 | tr -d '\r' | grep -q "successfully" && { echo OK; exit 0; } || { echo FAIL; exit 1; }
    ;;
  pid)
    P="$(hdc shell pidof "${2:?usage: pid <bundle>}" 2>/dev/null | tr -d '\r\n ')"
    [ -n "$P" ] && { echo "$P"; exit 0; } || exit 1
    ;;
  wait-ready)
    for _ in $(seq 1 30); do
      [ "$(hdc shell 'param get const.product.model' 2>/dev/null | tr -d '\r\n ')" = "emulator" ] && { echo READY; exit 0; }
      sleep 2
    done
    echo "wait-ready: TIMEOUT" >&2; exit 1
    ;;
  *)
    echo "usage: device.sh emu-start|emu-stop|install|start-app|pid|wait-ready ..." >&2
    exit 2
    ;;
esac
