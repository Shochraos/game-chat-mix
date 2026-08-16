#!/usr/bin/env bash

set -u

DISCORD_SINK="${DISCORD_SINK:-discord_sink}"
CATCHALL_SINK="${CATCHALL_SINK:-catchall_sink}"
DISCORD_DESC="${DISCORD_DESC:-Discord}"
CATCHALL_DESC="${CATCHALL_DESC:-All Other Audio}"
HW_SINK="${HW_SINK:-}"
CHAT_MATCH="${CHAT_MATCH:-discord|webrtc}"
INITIAL_VOLUME="${INITIAL_VOLUME:-50}"
EVENT_DEBOUNCE="${EVENT_DEBOUNCE:-0.05}"
RETRY_DELAY="${RETRY_DELAY:-1}"
RETRY_DELAY_MAX="${RETRY_DELAY_MAX:-30}"

declare -A SINK_INDEX_BY_NAME=()
declare -A OWNED_MODULE=()
SUBSCRIBER_PID=""

log() {
  printf 'gamechat: %s\n' "$*" >&2
}

die() {
  log "$*"
  exit 2
}

probe_chat_match() {
  [[ "" =~ $CHAT_MATCH ]]
}

validate_config() {
  local probe=0
  probe_chat_match 2>/dev/null || probe=$?
  if ((probe > 1)); then
    die "CHAT_MATCH is not a valid extended regular expression: '${CHAT_MATCH}'"
  fi

  if ! [[ $INITIAL_VOLUME =~ ^[0-9]+$ ]] || ((INITIAL_VOLUME > 100)); then
    die "INITIAL_VOLUME must be an integer percentage between 0 and 100: '${INITIAL_VOLUME}'"
  fi

  if ! [[ $EVENT_DEBOUNCE =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "EVENT_DEBOUNCE must be a number of seconds: '${EVENT_DEBOUNCE}'"
  fi

  if ! [[ $RETRY_DELAY =~ ^[1-9][0-9]*$ ]]; then
    die "RETRY_DELAY must be a positive whole number of seconds: '${RETRY_DELAY}'"
  fi

  if ! [[ $RETRY_DELAY_MAX =~ ^[1-9][0-9]*$ ]] || ((RETRY_DELAY_MAX < RETRY_DELAY)); then
    die "RETRY_DELAY_MAX must be a whole number of seconds not below RETRY_DELAY: '${RETRY_DELAY_MAX}'"
  fi

  if [[ $DISCORD_SINK == "$CATCHALL_SINK" ]]; then
    die "DISCORD_SINK and CATCHALL_SINK must differ: '${DISCORD_SINK}'"
  fi
}

refresh_sinks() {
  SINK_INDEX_BY_NAME=()
  local index name
  while IFS=$'\t' read -r index name _; do
    [[ $index =~ ^[0-9]+$ ]] || continue
    SINK_INDEX_BY_NAME["$name"]=$index
  done < <(pactl list short sinks 2>/dev/null)
}

remap_module_info() {
  local name="${1:-}"
  [[ -n $name ]] || return 1
  pactl list short modules 2>/dev/null | awk -F'\t' -v want="sink_name=${name}" '
      $2 != "module-remap-sink" { next }
      {
        id = ""
        master = ""
        count = split($3, arg, /[ \t]+/)
        for (i = 1; i <= count; i++) {
          if (arg[i] == want) id = $1
          else if (arg[i] ~ /^master=/) master = substr(arg[i], 8)
        }
        if (id != "") {
          gsub(/^"|"$/, "", master)
          print id "\t" master
          exit
        }
      }'
}

refresh_owned_modules() {
  OWNED_MODULE=()
  local id
  while read -r id; do
    [[ $id =~ ^[0-9]+$ ]] || continue
    OWNED_MODULE["$id"]=1
  done < <(pactl list short modules 2>/dev/null | awk -F'\t' \
    -v chat="sink_name=${DISCORD_SINK}" -v rest="sink_name=${CATCHALL_SINK}" '
      $2 != "module-remap-sink" { next }
      {
        count = split($3, arg, /[ \t]+/)
        for (i = 1; i <= count; i++)
          if (arg[i] == chat || arg[i] == rest) { print $1; next }
      }')
}

sink_volume_percent() {
  pactl get-sink-volume "${1:-}" 2>/dev/null | awk '
      NR == 1 {
        for (i = 1; i <= NF; i++)
          if ($i ~ /^[0-9]+%$/) { print substr($i, 1, length($i) - 1); exit }
      }'
}

set_sink_volume() {
  local sink="${1:-}" percent="${2:-}" attempt
  for ((attempt = 0; attempt < 20; attempt++)); do
    pactl set-sink-volume "$sink" "${percent}%" >/dev/null 2>&1 && return 0
    sleep 0.05
  done
  log "failed to set volume of '${sink}' to ${percent}%"
  return 1
}

resolve_hw_sink() {
  if [[ -n $HW_SINK ]]; then
    [[ -n ${SINK_INDEX_BY_NAME[$HW_SINK]:-} ]] && printf '%s' "$HW_SINK"
    return 0
  fi

  local default
  default=$(pactl get-default-sink 2>/dev/null || true)
  if [[ -n $default && $default != "$DISCORD_SINK" && $default != "$CATCHALL_SINK" &&
    -n ${SINK_INDEX_BY_NAME[$default]:-} ]]; then
    printf '%s' "$default"
    return 0
  fi

  pactl list short sinks 2>/dev/null |
    awk -F'\t' -v chat="$DISCORD_SINK" -v rest="$CATCHALL_SINK" '
      $2 != chat && $2 != rest { print $2; exit }'
}

ensure_remap_sink() {
  local name="${1:-}" hw="${2:-}" description="${3:-}"
  [[ -n $name && -n $hw ]] || return 1

  local id="" master=""
  IFS=$'\t' read -r id master < <(remap_module_info "$name") || true

  local volume=""
  if [[ -n $id ]]; then
    if [[ $master == "$hw" && -n ${SINK_INDEX_BY_NAME[$name]:-} ]]; then
      return 0
    fi
    [[ -n ${SINK_INDEX_BY_NAME[$name]:-} ]] && volume=$(sink_volume_percent "$name")
    pactl unload-module "$id" >/dev/null 2>&1 ||
      log "failed to unload stale module ${id} for sink '${name}'"
  fi

  if ! pactl load-module module-remap-sink sink_name="$name" master="$hw" \
    sink_properties=device.description="$description" >/dev/null 2>&1; then
    log "failed to create remap sink '${name}' on master '${hw}'"
    return 1
  fi

  set_sink_volume "$name" "${volume:-$INITIAL_VOLUME}"
  return 0
}

sync_sinks() {
  refresh_sinks

  local hw
  hw=$(resolve_hw_sink)
  if [[ -z $hw ]]; then
    log "no usable master sink (HW_SINK='${HW_SINK}')"
    return 1
  fi

  ensure_remap_sink "$DISCORD_SINK" "$hw" "$DISCORD_DESC" || return 1
  ensure_remap_sink "$CATCHALL_SINK" "$hw" "$CATCHALL_DESC" || return 1

  refresh_sinks
  refresh_owned_modules

  if [[ -z ${SINK_INDEX_BY_NAME[$DISCORD_SINK]:-} || -z ${SINK_INDEX_BY_NAME[$CATCHALL_SINK]:-} ]]; then
    log "remap sinks did not appear on master '${hw}'"
    return 1
  fi
  return 0
}

list_sink_inputs() {
  pactl list sink-inputs 2>/dev/null | awk '
      function propval(line) {
        sub(/^[^=]*=[ \t]*/, "", line)
        gsub(/^"|"$/, "", line)
        return line
      }
      function emit() {
        if (id != "")
          print id "\037" sink "\037" owner "\037" node "\037" app "\037" client "\037" binary
        id = ""; sink = ""; owner = ""; node = ""; app = ""; client = ""; binary = ""
      }
      $1 == "Sink" && $2 == "Input" && $3 ~ /^#[0-9]+$/ { emit(); id = substr($3, 2); next }
      id == "" { next }
      $1 == "Owner" && $2 == "Module:" && owner == "" { owner = $3; next }
      $1 == "Sink:" && sink == "" { sink = $2; next }
      $1 == "node.name" && node == "" { node = propval($0); next }
      $1 == "application.name" && app == "" { app = propval($0); next }
      $1 == "client.name" && client == "" { client = propval($0); next }
      $1 == "application.process.binary" && binary == "" { binary = propval($0); next }
      END { emit() }'
}

is_chat_stream() {
  [[ ${1,,} =~ $CHAT_MATCH ]]
}

is_own_stream() {
  local owner="${1:-}" node="${2:-}"
  [[ -n $owner && -n ${OWNED_MODULE[$owner]:-} ]] && return 0
  [[ $node == "output.${DISCORD_SINK}" || $node == "output.${CATCHALL_SINK}" ]]
}

route_once() {
  local chat_index="${SINK_INDEX_BY_NAME[$DISCORD_SINK]:-}"
  local rest_index="${SINK_INDEX_BY_NAME[$CATCHALL_SINK]:-}"
  [[ -n $chat_index && -n $rest_index ]] || return 1

  local id sink owner node app client binary target target_index
  while IFS=$'\037' read -r id sink owner node app client binary; do
    [[ $id =~ ^[0-9]+$ ]] || continue
    is_own_stream "$owner" "$node" && continue

    if is_chat_stream "${app}|${client}|${binary}|${node}"; then
      target=$DISCORD_SINK
      target_index=$chat_index
    else
      target=$CATCHALL_SINK
      target_index=$rest_index
    fi

    [[ $sink == "$target_index" ]] && continue
    pactl move-sink-input "$id" "$target" >/dev/null 2>&1 ||
      log "failed to move stream ${id} to '${target}'"
  done < <(list_sink_inputs)
  return 0
}

handle_events() {
  local line sync route
  while IFS= read -r line; do
    sync=0
    route=0
    while :; do
      case $line in
      *"'remove' on sink-input "*) ;;
      *"on sink-input "*) route=1 ;;
      *"'change' on sink "*) ;;
      *"on sink "*) sync=1 ;;
      *"on server"*) sync=1 ;;
      esac
      IFS= read -r -t "$EVENT_DEBOUNCE" line || break
    done

    if ((sync)); then
      sync_sinks || return 1
      route=1
    fi
    ((route)) && route_once
  done
  return 0
}

stop_subscriber() {
  [[ -n $SUBSCRIBER_PID ]] || return 0
  kill "$SUBSCRIBER_PID" 2>/dev/null
  wait "$SUBSCRIBER_PID" 2>/dev/null
  SUBSCRIBER_PID=""
}

watch_events() {
  local status=0
  exec 3< <(pactl subscribe 2>/dev/null)
  SUBSCRIBER_PID=$!
  handle_events <&3 || status=$?
  exec 3<&-
  stop_subscriber
  return "$status"
}

main() {
  validate_config
  trap 'exit 0' INT TERM
  trap stop_subscriber EXIT

  local delay=$RETRY_DELAY
  while :; do
    if sync_sinks; then
      delay=$RETRY_DELAY
      route_once
      watch_events
      log "event stream ended, reconnecting in ${delay}s"
    else
      log "retrying in ${delay}s"
    fi

    sleep "$delay"
    ((delay *= 2))
    ((delay > RETRY_DELAY_MAX)) && delay=$RETRY_DELAY_MAX
  done
}

main "$@"
