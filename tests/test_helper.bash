#!/usr/bin/env bash
# Test harness for gamechat_mix.sh and gamechat_balance.sh.
#
# Each bats file boots its own hermetic PipeWire session (setup_file):
# isolated HOME and XDG_* dirs, pipewire config pinned to the nix store's
# stock configs. Without this a desktop host leaks /etc/pipewire or
# ~/.config/pipewire drop-ins into the spawned daemons, and our daemons
# could reach the host session. The master sink is a null sink and every
# daemon spawn pins HW_SINK to it: WirePlumber's default-device policy
# cannot be controlled hermetically (with WP it overrides set-default-sink,
# without WP set-default-sink is "Not supported").
#
# WirePlumber runs with the stock config tree plus the repo's
# 99-gamechat-no-volume-restore.conf drop-in, mirroring production: without
# the opt-out WP restores sink volumes over the daemon's INITIAL_VOLUME
# writes when it recreates sinks.
#
# BATS runs every test, setup_file and teardown_file as a separate process,
# so nothing in-memory survives between them: session PIDs are exported and
# daemon/probe PIDs live in pidfiles under GCM_RUN, which is also how
# session_reset reaps strays after a failed test.
#
# Harness-only knobs (not script config; no README table row):
#   GCM_MIX_SCRIPT, GCM_BALANCE_SCRIPT — script under test,
#   default $REPO_ROOT/dms/…; install.bats points these at the installed copy.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GCM_MIX_SCRIPT="${GCM_MIX_SCRIPT:-$REPO_ROOT/dms/gamechat_mix.sh}"
GCM_BALANCE_SCRIPT="${GCM_BALANCE_SCRIPT:-$REPO_ROOT/dms/gamechat_balance.sh}"

GCM_MASTER="gcm_master"
GCM_ALT_MASTER="gcm_alt"
GCM_CHAT_SINK="discord_sink"
GCM_CATCHALL_SINK="catchall_sink"

wait_until() {
  local timeout="$1"
  shift
  local deadline=$(($(date +%s) + timeout))
  while :; do
    if "$@"; then return 0; fi
    (($(date +%s) >= deadline)) && return 1
    sleep 0.2
  done
}

session_start() {
  local base run pw_share wp_share
  base=$(mktemp -d /tmp/gcm-e2e-XXXXXX)
  GCM_LOGS=$(mktemp -d /tmp/gcm-e2e-logs-XXXXXX)
  run="$base/run"
  mkdir -p "$base/home/.config" "$base/home/.cache" "$base/empty-xdg" "$run/pulse" "$run/probes"
  chmod 700 "$run" "$run/pulse"
  export GCM_BASE="$base" GCM_RUN="$run" GCM_LOGS

  pw_share="$(dirname "$(readlink -f "$(command -v pipewire)")")/../share/pipewire"
  wp_share="$(dirname "$(readlink -f "$(command -v wireplumber)")")/../share/wireplumber"

  export HOME="$base/home"
  export XDG_CONFIG_HOME="$base/home/.config"
  export XDG_CONFIG_DIRS="$base/empty-xdg"
  export XDG_CACHE_HOME="$base/home/.cache"
  export XDG_RUNTIME_DIR="$run"
  export PIPEWIRE_CONFIG_DIR="$pw_share"

  # Stock WP config tree (copied because the store copy is read-only) plus
  # the production volume-restore opt-out for the two remap sinks.
  mkdir -p "$run/wp-config"
  cp -r "$wp_share/." "$run/wp-config/"
  chmod -R u+w "$run/wp-config"
  mkdir -p "$run/wp-config/wireplumber.conf.d"
  cp "$REPO_ROOT/wireplumber/99-gamechat-no-volume-restore.conf" \
    "$run/wp-config/wireplumber.conf.d/"
  export WIREPLUMBER_CONFIG_DIR="$run/wp-config"

  unset PULSE_SERVER PULSE_SINK PULSE_SOURCE PULSE_LATENCY_MSEC
  unset DBUS_SESSION_BUS_ADDRESS DBUS_SYSTEM_BUS_ADDRESS

  if pactl info >/dev/null 2>&1; then
    echo "a pulse server already answers in a fresh runtime dir" >&2
    return 1
  fi

  env -i PATH="$PATH" HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" PIPEWIRE_CONFIG_DIR="$PIPEWIRE_CONFIG_DIR" \
    pipewire >"$GCM_LOGS/pipewire.log" 2>&1 &
  PW_PID=$!
  sleep 1
  env -i PATH="$PATH" HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" PIPEWIRE_CONFIG_DIR="$PIPEWIRE_CONFIG_DIR" \
    pipewire-pulse >"$GCM_LOGS/pipewire-pulse.log" 2>&1 &
  PWP_PID=$!
  env -i PATH="$PATH" HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" WIREPLUMBER_CONFIG_DIR="$WIREPLUMBER_CONFIG_DIR" \
    wireplumber >"$GCM_LOGS/wireplumber.log" 2>&1 &
  WP_PID=$!
  export PW_PID PWP_PID WP_PID

  wait_until 15 pactl info >/dev/null 2>&1 || {
    echo "hermetic session did not come up; logs in $GCM_LOGS" >&2
    return 1
  }

  MASTER_MODULE_ID=$(pactl load-module module-null-sink sink_name="$GCM_MASTER")
  [ -n "$MASTER_MODULE_ID" ] || {
    echo "failed to load the master null sink" >&2
    return 1
  }
  export MASTER_MODULE_ID
}

session_stop() {
  daemon_stop
  probes_stop
  if [ -n "${PW_PID:-}" ]; then
    kill "$PW_PID" "$PWP_PID" "$WP_PID" 2>/dev/null
    wait 2>/dev/null
  fi
  [ -n "${GCM_BASE:-}" ] && rm -rf "$GCM_BASE"
  PW_PID=""
  PWP_PID=""
  WP_PID=""
  MASTER_MODULE_ID=""
}

session_reset() {
  daemon_stop
  probes_stop
  unload_remaps
  unload_null_sink "$GCM_ALT_MASTER"
  if [ -z "$(sink_index "$GCM_MASTER")" ]; then
    MASTER_MODULE_ID=$(pactl load-module module-null-sink sink_name="$GCM_MASTER")
    export MASTER_MODULE_ID
  fi
}

daemon_start() {
  GCM_LOCK_FILE="$GCM_RUN/gamechat_mix.lock"
  DAEMON_LOG="$GCM_LOGS/daemon.log"
  : >"$DAEMON_LOG"
  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    HW_SINK="$GCM_MASTER" \
    LOCK_FILE="$GCM_LOCK_FILE" \
    "$@" \
    bash "$GCM_MIX_SCRIPT" >"$DAEMON_LOG" 2>&1 &
  DAEMON_PID=$!
  printf '%s\n' "$DAEMON_PID" >"$GCM_RUN/daemon.pid"
  export DAEMON_PID DAEMON_LOG GCM_LOCK_FILE
}

daemon_stop() {
  local pid="${DAEMON_PID:-}"
  if [ -z "$pid" ] && [ -n "${GCM_RUN:-}" ] && [ -f "$GCM_RUN/daemon.pid" ]; then
    pid=$(cat "$GCM_RUN/daemon.pid")
  fi
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null
  (
    sleep 10
    kill -KILL "$pid" 2>/dev/null
  ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  rm -f "$GCM_RUN/daemon.pid"
  DAEMON_PID=""
}

daemon_gone() {
  [ ! -d "/proc/$DAEMON_PID" ]
}

probe_start() {
  local pid
  env -i PATH="$PATH" HOME="$HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    paplay --device="$GCM_MASTER" --client-name="$1" --raw --rate=48000 \
    --channels=2 --format=s16le /dev/zero >/dev/null 2>&1 &
  pid=$!
  printf '%s\n' "$pid" >"$GCM_RUN/probes/$pid.pid"
  GCM_PROBE_PIDS+=("$pid")
}

probes_stop() {
  local file pid
  for file in "${GCM_RUN:-}"/probes/*.pid; do
    [ -f "$file" ] || continue
    pid=$(cat "$file")
    kill "$pid" 2>/dev/null
    rm -f "$file"
  done
  GCM_PROBE_PIDS=()
}

sink_exists() {
  pactl list short sinks 2>/dev/null | awk -F'\t' -v want="$1" \
    '$2 == want { found = 1 } END { exit found ? 0 : 1 }'
}

sink_absent() {
  ! sink_exists "$1"
}

sink_index() {
  pactl list short sinks 2>/dev/null | awk -F'\t' -v want="$1" '$2 == want { print $1; exit }'
}

sink_volume() {
  pactl get-sink-volume "$1" 2>/dev/null | awk 'NR == 1 {
    for (i = 1; i <= NF; i++)
      if ($i ~ /^[0-9]+%$/) { print substr($i, 1, length($i) - 1); exit }
  }'
}

set_volume_retry() {
  local sink="$1" pct="$2" i
  # pactl accepts the write before a fresh remap device applies it, so
  # verify the read-back and keep retrying instead of trusting one success.
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    pactl set-sink-volume "$sink" "$pct%" >/dev/null 2>&1 || {
      sleep 0.1
      continue
    }
    [ "$(sink_volume "$sink")" = "$pct" ] && return 0
    sleep 0.1
  done
  return 1
}

module_id_of_sink() {
  pactl list short modules 2>/dev/null | awk -F'\t' -v want="sink_name=$1" '
    $2 != "module-remap-sink" { next }
    {
      n = split($3, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] == want) { print $1; exit }
    }'
}

module_master_of() {
  pactl list short modules 2>/dev/null | awk -F'\t' -v want="sink_name=$1" '
    $2 != "module-remap-sink" { next }
    {
      n = split($3, a, /[ \t]+/); id = ""; m = ""
      for (i = 1; i <= n; i++) {
        if (a[i] == want) id = $1
        else if (a[i] ~ /^master=/) m = substr(a[i], 8)
      }
      if (id != "") { gsub(/^"|"$/, "", m); print m; exit }
    }'
}

unload_remaps() {
  pactl list short modules 2>/dev/null | awk -F'\t' '$2 == "module-remap-sink" { print $1 }' |
    xargs -r -n1 pactl unload-module
  return 0
}

unload_null_sink() {
  local id
  id=$(pactl list short modules 2>/dev/null | awk -F'\t' -v want="sink_name=$1" '
    $2 != "module-null-sink" { next }
    {
      n = split($3, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] == want) { print $1; exit }
    }')
  [ -n "$id" ] && pactl unload-module "$id" >/dev/null 2>&1
  return 0
}

load_remap() {
  pactl load-module module-remap-sink sink_name="$1" master="$2" \
    sink_properties="device.description=$3" >/dev/null
}

stream_id_of_client() {
  pactl list sink-inputs 2>/dev/null | awk -v want="$1" '
    function propval(line) { sub(/^[^=]*=[ \t]*/, "", line); gsub(/^"|"$/, "", line); return line }
    function flush() { if (id != "" && (app == want || client == want)) print id; id = ""; app = ""; client = "" }
    $1 == "Sink" && $2 == "Input" && $3 ~ /^#[0-9]+$/ { flush(); id = substr($3, 2); next }
    id == "" { next }
    $1 == "application.name" && app == "" { app = propval($0); next }
    $1 == "client.name" && client == "" { client = propval($0); next }
    END { flush() }'
}

stream_sink_index_of_client() {
  pactl list sink-inputs 2>/dev/null | awk -v want="$1" '
    function propval(line) { sub(/^[^=]*=[ \t]*/, "", line); gsub(/^"|"$/, "", line); return line }
    function flush() { if (id != "" && (app == want || client == want)) print sink; id = ""; sink = ""; app = ""; client = "" }
    $1 == "Sink" && $2 == "Input" && $3 ~ /^#[0-9]+$/ { flush(); id = substr($3, 2); next }
    id == "" { next }
    $1 == "Sink:" && sink == "" { sink = $2; next }
    $1 == "application.name" && app == "" { app = propval($0); next }
    $1 == "client.name" && client == "" { client = propval($0); next }
    END { flush() }'
}

wait_sink_exists() {
  wait_until "${2:-10}" sink_exists "$1"
}

wait_volume() {
  local sink="$1" want="$2" timeout="${3:-10}"
  local deadline=$(($(date +%s) + timeout))
  while :; do
    [ "$(sink_volume "$sink")" = "$want" ] && return 0
    (($(date +%s) >= deadline)) && {
      echo "timeout: volume of '$sink' never became ${want}% (now $(sink_volume "$sink"))" >&2
      return 1
    }
    sleep 0.2
  done
}

wait_stream_on() {
  local client="$1" sink="$2" timeout="${3:-10}"
  local target deadline
  target=$(sink_index "$sink")
  deadline=$(($(date +%s) + timeout))
  while :; do
    [ "$(stream_sink_index_of_client "$client")" = "$target" ] && return 0
    (($(date +%s) >= deadline)) && {
      echo "timeout: '$client' never reached '$sink'" >&2
      return 1
    }
    sleep 0.2
  done
}

wait_daemon_log() {
  local pattern="$1" timeout="${2:-10}"
  local deadline=$(($(date +%s) + timeout))
  while :; do
    grep -q "$pattern" "$DAEMON_LOG" 2>/dev/null && return 0
    (($(date +%s) >= deadline)) && return 1
    sleep 0.2
  done
}

setup_file() {
  session_start
}

teardown_file() {
  session_stop
}

setup() {
  session_reset
}

teardown() {
  session_reset
}
