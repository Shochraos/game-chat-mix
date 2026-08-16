#!/usr/bin/env bash

set -u

DISCORD_SINK="${DISCORD_SINK:-discord_sink}"
CATCHALL_SINK="${CATCHALL_SINK:-catchall_sink}"
HW_SINK="${HW_SINK:-}"

sink_exists() {
  pactl list short sinks 2>/dev/null | awk -v s="${1:-}" '$2==s {found=1} END{exit !found}'
}

resolve_hw_sink() {
  if [[ -n $HW_SINK ]]; then
    printf '%s' "$HW_SINK"
    return 0
  fi
  local d
  d=$(pactl get-default-sink 2>/dev/null || true)
  if [[ -z $d || $d == "$DISCORD_SINK" || $d == "$CATCHALL_SINK" ]]; then
    d=$(pactl list short sinks 2>/dev/null |
      awk -v a="$DISCORD_SINK" -v b="$CATCHALL_SINK" '$2!=a && $2!=b {print $2; exit}')
  fi
  printf '%s' "$d"
}

find_module_for_sink() {
  local sink_name="${1:-}"
  if [[ -z $sink_name ]]; then return 1; fi
  pactl list modules 2>/dev/null | awk -v s="sink_name=${sink_name}" '
      BEGIN{RS=""; FS="\n"}
      $0 ~ s { if (match($0, /Module #([0-9]+)/, m)) print m[1] }
    '
}

get_module_master() {
  local mid="${1:-}"
  if [[ -z $mid ]]; then return 1; fi
  local arg
  arg=$(pactl list modules 2>/dev/null | awk -v id="Module #${mid}" 'BEGIN{RS="";FS="\n"} $0 ~ id {
         for(i=1;i<=NF;i++) if ($i ~ /Argument:/) { print $i; exit }
    }' || true)
  if [[ -z $arg ]]; then
    printf ''
    return
  fi
  local m
  m=$(printf '%s' "$arg" | sed -n 's/.*master=\([^ ]*\).*/\1/p' | tr -d '"' || true)
  printf '%s' "$m"
}

ensure_remap_sink() {
  local name="${1:-}"
  local hw="${2:-}"
  local desc="${3:-Manual remap}"
  if [[ -z $name || -z $hw ]]; then return 1; fi
  local mid
  mid=$(find_module_for_sink "$name" || true)
  if [[ -n $mid ]]; then
    local master
    master=$(get_module_master "$mid" || true)
    if [[ $master == "$hw" ]]; then
      return 0
    else
      pactl unload-module "$mid" >/dev/null 2>&1
    fi
  fi
  if ! pactl load-module module-remap-sink sink_name="$name" master="$hw" \
    sink_properties=device.description="$desc" >/dev/null 2>&1; then
    echo "gamechat: failed to create remap sink '$name' on master '$hw'" >&2
    return 1
  fi
  sleep 0.05
  return 2
}

sync_sinks() {
  local hw created=0
  hw=$(resolve_hw_sink)
  if [[ -z $hw ]] || ! sink_exists "$hw"; then
    echo "gamechat: no usable master sink (HW_SINK='${HW_SINK}')" >&2
    return 1
  fi

  ensure_remap_sink "$DISCORD_SINK" "$hw" "Discord"
  [[ $? -eq 2 ]] && created=1
  ensure_remap_sink "$CATCHALL_SINK" "$hw" "All Other Audio"
  [[ $? -eq 2 ]] && created=1

  if [[ $created -eq 1 ]]; then
    sleep 0.15
    pactl set-sink-volume "$DISCORD_SINK" 50% >/dev/null 2>&1
    pactl set-sink-volume "$CATCHALL_SINK" 50% >/dev/null 2>&1
  fi
  return 0
}

move_sink_input_safe() {
  local id="${1:-}"
  local dest="${2:-}"
  if ! [[ $id =~ ^[0-9]+$ ]]; then return 1; fi
  pactl move-sink-input "$id" "$dest" >/dev/null 2>&1
}

declare -A SINK_NAME_BY_INDEX

load_sink_names() {
  SINK_NAME_BY_INDEX=()
  local idx name rest
  while IFS=$'\t' read -r idx name rest; do
    if [[ $idx =~ ^[0-9]+$ ]]; then SINK_NAME_BY_INDEX[$idx]="$name"; fi
  done < <(pactl list short sinks 2>/dev/null)
}

list_sink_inputs() {
  pactl list sink-inputs 2>/dev/null | awk '
      function propval(s) {
        sub(/^[^=]*=[ \t]*/, "", s)
        gsub(/^"|"$/, "", s)
        return s
      }
      function flush() {
        if (id != "") print id "\037" cur "\037" node "\037" app "\037" client "\037" bin
        id=""; cur=""; node=""; app=""; client=""; bin=""
      }
      $1=="Sink" && $2=="Input" && $3 ~ /^#[0-9]+$/ { flush(); id=substr($3, 2); next }
      id=="" { next }
      $1=="Sink:" && cur=="" { cur=$2; next }
      $1=="node.name" && node=="" { node=propval($0); next }
      $1=="application.name" && app=="" { app=propval($0); next }
      $1=="client.name" && client=="" { client=propval($0); next }
      $1=="application.process.binary" && bin=="" { bin=propval($0); next }
      END { flush() }'
}

is_chat_stream() {
  local ident="${1,,}"
  [[ $ident == *discord* || $ident == *webrtc* ]]
}

route_once() {
  load_sink_names
  local id cur node app client bin dest
  while IFS=$'\037' read -r id cur node app client bin; do
    if ! [[ $id =~ ^[0-9]+$ ]]; then continue; fi
    if [[ $node == output.* ]]; then continue; fi
    if is_chat_stream "$app|$client|$bin|$node"; then
      dest="$DISCORD_SINK"
    else
      dest="$CATCHALL_SINK"
    fi
    if [[ ${SINK_NAME_BY_INDEX[$cur]:-} == "$dest" ]]; then continue; fi
    move_sink_input_safe "$id" "$dest"
  done < <(list_sink_inputs)
}

# MAIN
sync_sinks || exit 1
route_once

pactl subscribe 2>/dev/null | while read -r L; do
  case "$L" in
  *"on sink-input"*)
    sleep 0.05
    route_once
    ;;
  *"on server"*)
    sync_sinks && route_once
    ;;
  esac
done
