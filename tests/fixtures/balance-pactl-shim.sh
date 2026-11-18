#!/usr/bin/env bash

set -euo pipefail

if [[ ${SHIM_REQUIRE_C:-} == 1 && ${LC_ALL:-} != C ]]; then
  exit 1
fi

case "$1" in
get-sink-volume)
  volume=$(<"$SHIM_STATE/$2")
  if [[ "$2" == "$DISCORD_SINK" && -n ${SHIM_READ_DELAY:-} ]]; then
    sleep "$SHIM_READ_DELAY"
  fi
  printf 'Volume: front-left: 1 / %s%% / 0.00 dB\n' "$volume"
  [[ "$2" != "${SHIM_FAIL_READ:-}" ]]
  ;;
set-sink-volume)
  printf '%s\n' "$2" >>"$SHIM_STATE/writes"
  if [[ "$2" == "${SHIM_FAIL_SINK:-}" ]]; then
    if [[ -n ${SHIM_EXTERNAL_VOLUME:-} ]]; then
      printf '%s\n' "$SHIM_EXTERNAL_VOLUME" >"$SHIM_STATE/$DISCORD_SINK"
    fi
    exit 1
  fi
  printf '%s\n' "${3%%%}" >"$SHIM_STATE/$2"
  ;;
*) exit 1 ;;
esac
