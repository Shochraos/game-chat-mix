#!/usr/bin/env bash

set -euo pipefail

DISCORD_SINK="${DISCORD_SINK:-discord_sink}"
CATCHALL_SINK="${CATCHALL_SINK:-catchall_sink}"
STEP="${STEP:-2}"
RESET_VOLUME="${RESET_VOLUME:-50}"

die() {
  printf 'gamechat: %s\n' "$*" >&2
  exit 1
}

validate_config() {
  if ! [[ $STEP =~ ^[1-9][0-9]*$ ]] || ((STEP > 100)); then
    die "STEP must be an integer percentage between 1 and 100: '${STEP}'"
  fi

  if ! [[ $RESET_VOLUME =~ ^[0-9]+$ ]] || ((RESET_VOLUME > 100)); then
    die "RESET_VOLUME must be an integer percentage between 0 and 100: '${RESET_VOLUME}'"
  fi
}

sink_volume_percent() {
  local sink="$1" percent
  percent=$(pactl get-sink-volume "$sink" 2>/dev/null | awk '
      NR == 1 {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^[0-9]+%$/) { print substr($i, 1, length($i) - 1); exit }
      }' || true)
  [[ -n $percent ]] || die "cannot read the volume of sink '${sink}'; is gamechat_mix running?"
  printf '%s' "$percent"
}

set_volume() {
  local sink="$1" percent="$2"
  pactl set-sink-volume "$sink" "${percent}%" >/dev/null 2>&1 ||
    die "cannot set the volume of sink '${sink}'; is gamechat_mix running?"
}

adjust_volume() {
  local sink="$1" delta="$2" current target
  current=$(sink_volume_percent "$sink")
  target=$((current + delta))
  if ((target < 0)); then
    target=0
  elif ((target > 100)); then
    target=100
  fi
  set_volume "$sink" "$target"
}

shift_balance() {
  adjust_volume "$DISCORD_SINK" "$1"
  adjust_volume "$CATCHALL_SINK" "$2"
}

validate_config

case "${1:-}" in
chat) shift_balance "$STEP" "-${STEP}" ;;
game) shift_balance "-${STEP}" "$STEP" ;;
reset)
  set_volume "$DISCORD_SINK" "$RESET_VOLUME"
  set_volume "$CATCHALL_SINK" "$RESET_VOLUME"
  ;;
*)
  printf 'usage: %s chat|game|reset\n' "${0##*/}" >&2
  exit 1
  ;;
esac
