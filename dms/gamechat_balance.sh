#!/usr/bin/env bash

set -euo pipefail
export LC_ALL=C

DISCORD_SINK="${DISCORD_SINK:-discord_sink}"
CATCHALL_SINK="${CATCHALL_SINK:-catchall_sink}"
STEP="${STEP:-2}"
RESET_VOLUME="${RESET_VOLUME:-50}"

log() {
  printf 'gamechat: %s\n' "$*" >&2
}

die() {
  log "$*"
  exit 1
}

validate_config() {
  if ! [[ $STEP =~ ^([1-9][0-9]?|100)$ ]]; then
    die "STEP must be an integer percentage between 1 and 100: '${STEP}'"
  fi

  if ! [[ $RESET_VOLUME =~ ^0*([0-9]{1,2}|100)$ ]]; then
    die "RESET_VOLUME must be an integer percentage between 0 and 100: '${RESET_VOLUME}'"
  fi
  RESET_VOLUME=$((10#${BASH_REMATCH[1]}))
}

acquire_lock() {
  local lock_dir="${XDG_RUNTIME_DIR:-}"
  umask 077
  if [[ -z $lock_dir ]]; then
    lock_dir="${XDG_CACHE_HOME:-${HOME:?HOME is required without XDG_RUNTIME_DIR}/.cache}/gamechat-mix"
    mkdir -p -- "$lock_dir" || die "cannot create balance lock directory '${lock_dir}'"
  fi
  exec 9>>"$lock_dir/gamechat_balance.lock" || die "cannot open the balance lock in '${lock_dir}'"
  flock -x 9 || die "cannot acquire the balance lock in '${lock_dir}'"
}

sink_volume_percent() {
  local sink="$1" percent
  percent=$(pactl get-sink-volume "$sink" 2>/dev/null | awk '
      NR == 1 {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^[0-9]+%$/) { print substr($i, 1, length($i) - 1); break }
      }') && [[ $percent =~ ^[0-9]{1,9}$ ]] ||
    die "cannot read the volume of sink '${sink}'; is gamechat_mix running?"
  printf '%s' "$percent"
}

shifted_volume() {
  local target=$((10#$1 + $2))
  if ((target < 0)); then
    target=0
  elif ((target > 100)); then
    target=100
  fi
  printf '%s' "$target"
}

set_balance() {
  local chat_target="$1" game_target="$2"
  pactl set-sink-volume "$DISCORD_SINK" "${chat_target}%" >/dev/null 2>&1 ||
    die "cannot set the volume of sink '${DISCORD_SINK}'; is gamechat_mix running?"
  if ! pactl set-sink-volume "$CATCHALL_SINK" "${game_target}%" >/dev/null 2>&1; then
    log "partial update: set '${DISCORD_SINK}' to ${chat_target}%, but could not set '${CATCHALL_SINK}' to ${game_target}%"
    exit 2
  fi
}

validate_config

case "${1:-}" in
chat | game | reset) ;;
*)
  printf 'usage: %s chat|game|reset\n' "${0##*/}" >&2
  exit 1
  ;;
esac

acquire_lock
chat_volume=$(sink_volume_percent "$DISCORD_SINK")
game_volume=$(sink_volume_percent "$CATCHALL_SINK")

case "$1" in
chat) set_balance "$(shifted_volume "$chat_volume" "$STEP")" "$(shifted_volume "$game_volume" "-$STEP")" ;;
game) set_balance "$(shifted_volume "$chat_volume" "-$STEP")" "$(shifted_volume "$game_volume" "$STEP")" ;;
reset) set_balance "$RESET_VOLUME" "$RESET_VOLUME" ;;
esac
