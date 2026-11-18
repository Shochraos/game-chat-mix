#!/usr/bin/env bash
set -u

case "$1" in
subscribe)
  case "$GCM_PACTL_MODE" in
  delayed)
    generation=1
    [[ ! -e $GCM_PACTL_STATE/subscriber.1 ]] || generation=2
    printf '%s\n' "$BASHPID" >"$GCM_PACTL_STATE/subscriber.$generation"
    until [[ -e $GCM_PACTL_STATE/register.$generation ]]; do sleep 0.05; done
    ;;
  flood | zero)
    touch "$GCM_PACTL_STATE/subscriber.ready"
    until [[ -e $GCM_PACTL_STATE/send ]]; do sleep 0.05; done
    event="Event 'change' on sink-input #17"
    printf '%s\n%s\n' "$event" "$event"
    if [[ $GCM_PACTL_MODE == flood ]]; then
      while :; do
        printf '%s\n' "$event"
        sleep 0.01
      done
    fi
    while :; do sleep 0.05; done
    ;;
  esac
  ;;
load-module)
  if [[ $GCM_PACTL_MODE == volume && $3 == sink_name=discord_sink && -e $GCM_PACTL_STATE/block-load ]]; then
    exit 1
  fi
  ;;
set-sink-volume)
  if [[ $GCM_PACTL_MODE == volume && $2 == discord_sink && ! -e $GCM_PACTL_STATE/allow-volume ]]; then
    exit 0
  fi
  ;;
get-default-sink | list)
  if [[ $GCM_PACTL_MODE == locale && ${LC_ALL:-} != C ]]; then
    printf '%s\n' "unexpected pactl locale: ${LC_ALL:-unset}" >"$GCM_PACTL_STATE/bad-locale"
    exit 1
  fi
  ;;
esac

exec "$GCM_REAL_PACTL" "$@"
