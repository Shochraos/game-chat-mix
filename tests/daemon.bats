#!/usr/bin/env bats

load 'test_helper'

@test "fresh start creates both remap sinks on the master at INITIAL_VOLUME" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"
  wait_sink_exists "$GCM_CATCHALL_SINK"
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
  [ "$(module_master_of "$GCM_CHAT_SINK")" = "$GCM_MASTER" ]
  [ "$(module_master_of "$GCM_CATCHALL_SINK")" = "$GCM_MASTER" ]
}

@test "adoption keeps existing sinks: volumes and module ids untouched" {
  load_remap "$GCM_CHAT_SINK" "$GCM_MASTER" "Discord"
  load_remap "$GCM_CATCHALL_SINK" "$GCM_MASTER" "All Other Audio"
  set_volume_retry "$GCM_CHAT_SINK" 30
  set_volume_retry "$GCM_CATCHALL_SINK" 30
  local chat_id catch_id
  chat_id=$(module_id_of_sink "$GCM_CHAT_SINK")
  catch_id=$(module_id_of_sink "$GCM_CATCHALL_SINK")

  daemon_start
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK"

  [ "$(module_id_of_sink "$GCM_CHAT_SINK")" = "$chat_id" ]
  [ "$(module_id_of_sink "$GCM_CATCHALL_SINK")" = "$catch_id" ]
  [ "$(sink_volume "$GCM_CHAT_SINK")" = "30" ]
  [ "$(sink_volume "$GCM_CATCHALL_SINK")" = "30" ]
}

@test "chat-labelled stream lands on discord_sink, others on catchall_sink" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"
  probe_start "WEBRTC VoiceEngine"
  probe_start "gcm-probe-game"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK"
  wait_stream_on "gcm-probe-game" "$GCM_CATCHALL_SINK"
}

@test "routing wait rejects a missing stream and a missing sink" {
  run wait_stream_on "nonexistent client" "$GCM_CHAT_SINK" 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"nonexistent client"* ]]
  run wait_stream_on "nonexistent client" "$GCM_MASTER" 0
  [ "$status" -eq 1 ]
}

@test "forcibly moved chat stream is pulled back" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK"

  local stream_id
  stream_id=$(stream_id_of_client "WEBRTC VoiceEngine")
  [[ $stream_id =~ ^[0-9]+$ ]]
  pactl move-sink-input "$stream_id" "$GCM_CATCHALL_SINK"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK"
}

@test "lost master backs off and recovers when it re-appears" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"

  pactl unload-module "$MASTER_MODULE_ID"
  wait_daemon_log "no usable master sink" 15
  kill -0 "$DAEMON_PID"

  pactl load-module module-null-sink sink_name="$GCM_MASTER" >/dev/null
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 15
}

@test "externally unloaded remap modules are recreated at INITIAL_VOLUME" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"
  set_volume_retry "$GCM_CHAT_SINK" 65
  wait_volume "$GCM_CHAT_SINK" 65

  local chat_id catch_id
  chat_id=$(module_id_of_sink "$GCM_CHAT_SINK")
  catch_id=$(module_id_of_sink "$GCM_CATCHALL_SINK")
  [[ $chat_id =~ ^[0-9]+$ && $catch_id =~ ^[0-9]+$ ]]
  pactl unload-module "$chat_id"
  pactl unload-module "$catch_id"

  wait_sink_exists "$GCM_CHAT_SINK" 15
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
  [[ $(module_id_of_sink "$GCM_CHAT_SINK") != "$chat_id" ]]
  [[ $(module_id_of_sink "$GCM_CATCHALL_SINK") != "$catch_id" ]]
}

@test "killed pactl subscribe child reconnects and routing resumes" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"

  local sub
  sub=$(wait_until 5 daemon_subscriber)
  [[ $sub =~ ^[0-9]+$ ]]
  kill "$sub"
  wait_daemon_log "event stream ended, reconnecting" 15

  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 15
}

@test "without HW_SINK the master resolves to an existing non-remap sink" {
  daemon_start HW_SINK=
  wait_sink_exists "$GCM_CHAT_SINK" 15

  local master
  master=$(module_master_of "$GCM_CHAT_SINK")
  [ -n "$master" ]
  [ "$master" != "$GCM_CHAT_SINK" ]
  [ "$master" != "$GCM_CATCHALL_SINK" ]
  sink_exists "$master"
}

@test "second instance exits cleanly on the held lock" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"

  local before after
  before=$(pactl list short modules 2>/dev/null | awk -F'\t' '$2 == "module-remap-sink"' | wc -l)
  run env HW_SINK="$GCM_MASTER" LOCK_FILE="$GCM_LOCK_FILE" bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"another instance already holds"* ]]
  after=$(pactl list short modules 2>/dev/null | awk -F'\t' '$2 == "module-remap-sink"' | wc -l)
  [ "$after" = "$before" ]
}

@test "supervised daemon waits for the lock and routes after handover" {
  local lock="$GCM_RUN/held.lock"
  exec 8>"$lock"
  flock 8
  daemon_start GAMECHAT_WAIT_FOR_LOCK=1 LOCK_FILE="$lock" 8>&-
  wait_daemon_log 'waiting for' 3
  kill -0 "$DAEMON_PID"
  sink_absent "$GCM_CHAT_SINK"
  sink_absent "$GCM_CATCHALL_SINK"
  exec 8>&-

  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK"
}

@test "TERM cancels a supervised lock waiter without taking the lock later" {
  local lock="$GCM_RUN/held.lock"
  exec 8>"$lock"
  flock 8
  daemon_start GAMECHAT_WAIT_FOR_LOCK=1 LOCK_FILE="$lock" 8>&-
  wait_daemon_log 'waiting for' 3
  local children
  children=$(pgrep -P "$DAEMON_PID" || true)
  kill -TERM "$DAEMON_PID"
  wait_until 2 daemon_gone
  wait "$DAEMON_PID"
  local child
  for child in $children; do
    [ ! -d "/proc/$child" ]
  done
  exec 8>&-
  flock -n "$lock" true
  sink_absent "$GCM_CHAT_SINK"
}

@test "TERM shuts down cleanly and reaps the subscriber" {
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"

  local sub
  sub=$(wait_until 5 daemon_subscriber)
  [[ $sub =~ ^[0-9]+$ ]]

  kill -TERM "$DAEMON_PID"
  (
    sleep 10
    kill -KILL "$DAEMON_PID" 2>/dev/null
  ) &
  local watchdog=$!
  local daemon_status=0
  wait "$DAEMON_PID" || daemon_status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  [ "$daemon_status" -eq 0 ]
  wait_until 5 daemon_gone
  ! kill -0 "$sub" 2>/dev/null
}

@test "INT shuts down cleanly and reaps the subscriber" {
  set -m
  daemon_start
  set +m
  wait_sink_exists "$GCM_CHAT_SINK"

  local sub
  sub=$(wait_until 5 daemon_subscriber)
  [[ $sub =~ ^[0-9]+$ ]]

  kill -INT "$DAEMON_PID"
  (
    sleep 10
    kill -KILL "$DAEMON_PID" 2>/dev/null
  ) &
  local watchdog=$!
  local daemon_status=0
  wait "$DAEMON_PID" || daemon_status=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  [ "$daemon_status" -eq 0 ]
  wait_until 5 daemon_gone
  ! kill -0 "$sub" 2>/dev/null
}
