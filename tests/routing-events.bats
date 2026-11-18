#!/usr/bin/env bats

load 'test_helper'

setup() {
  session_reset
  SHIM_STATE="$BATS_TEST_TMPDIR/pactl-state"
  SHIM_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$SHIM_STATE" "$SHIM_BIN"
  cp "$REPO_ROOT/tests/fixtures/routing-pactl.sh" "$SHIM_BIN/pactl"
  chmod +x "$SHIM_BIN/pactl"
}

shim_daemon_start() {
  local mode="$1"
  shift
  daemon_start PATH="$SHIM_BIN:$PATH" GCM_REAL_PACTL="$(command -v pactl)" \
    GCM_PACTL_STATE="$SHIM_STATE" GCM_PACTL_MODE="$mode" "$@"
}

@test "pactl parsing uses the C locale regardless of inherited locale" {
  shim_daemon_start locale LC_ALL=POSIX LANGUAGE=de LANG=de_DE.UTF-8
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 4
  [ ! -e "$SHIM_STATE/bad-locale" ]
}

@test "an acknowledged but unapplied initial volume is retried on the same sink" {
  shim_daemon_start volume INITIAL_VOLUME=027
  wait_sink_exists "$GCM_CHAT_SINK"
  local chat_id
  chat_id=$(module_id_of_sink "$GCM_CHAT_SINK")
  [[ $chat_id =~ ^[0-9]+$ ]]
  wait_daemon_log 'failed to set volume' 4
  touch "$SHIM_STATE/allow-volume"
  wait_volume "$GCM_CHAT_SINK" 27
  wait_volume "$GCM_CATCHALL_SINK" 27
  [ "$(module_id_of_sink "$GCM_CHAT_SINK")" = "$chat_id" ]
}

@test "volume captured from a stale remap survives a failed write and retry" {
  pactl load-module module-null-sink sink_name="$GCM_ALT_MASTER" >/dev/null
  load_remap "$GCM_CHAT_SINK" "$GCM_ALT_MASTER" Discord
  set_volume_retry "$GCM_CHAT_SINK" 73

  touch "$SHIM_STATE/block-load"
  shim_daemon_start volume INITIAL_VOLUME=27
  wait_daemon_log 'failed to create remap sink' 4
  sink_absent "$GCM_CHAT_SINK"
  rm "$SHIM_STATE/block-load"
  wait_daemon_log 'failed to set volume' 8
  touch "$SHIM_STATE/allow-volume"
  wait_volume "$GCM_CHAT_SINK" 73
  [ "$(module_master_of "$GCM_CHAT_SINK")" = "$GCM_MASTER" ]
  wait_volume "$GCM_CATCHALL_SINK" 27
}

@test "a stream missed before subscribe registration is routed after startup" {
  shim_daemon_start delayed
  wait_until 4 test -s "$SHIM_STATE/subscriber.1"
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_MASTER" 3
  touch "$SHIM_STATE/register.1"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 9
}

@test "a stream missed before subscribe registration is routed after reconnect" {
  shim_daemon_start delayed
  wait_until 4 test -s "$SHIM_STATE/subscriber.1"
  touch "$SHIM_STATE/register.1"
  local sub
  sub=$(wait_until 5 daemon_subscriber)
  [[ $sub =~ ^[0-9]+$ ]]
  kill "$sub"
  wait_until 5 test -s "$SHIM_STATE/subscriber.2"
  probe_start "gcm-reconnect-game"
  wait_stream_on "gcm-reconnect-game" "$GCM_MASTER" 3
  touch "$SHIM_STATE/register.2"
  wait_stream_on "gcm-reconnect-game" "$GCM_CATCHALL_SINK" 9
}

@test "a stream is routed while relevant events keep arriving" {
  shim_daemon_start flood EVENT_DEBOUNCE=0.2
  wait_until 4 test -f "$SHIM_STATE/subscriber.ready"
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_MASTER" 3
  touch "$SHIM_STATE/send"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 3
}

@test "zero debounce processes queued events instead of only checking readiness" {
  shim_daemon_start zero EVENT_DEBOUNCE=0.000
  wait_until 4 test -f "$SHIM_STATE/subscriber.ready"
  probe_start "WEBRTC VoiceEngine"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_MASTER" 3
  touch "$SHIM_STATE/send"
  wait_stream_on "WEBRTC VoiceEngine" "$GCM_CHAT_SINK" 3
}
