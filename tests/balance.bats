#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  session_start
  load_remap "$GCM_CHAT_SINK" "$GCM_MASTER" "Discord"
  load_remap "$GCM_CATCHALL_SINK" "$GCM_MASTER" "All Other Audio"
}

setup() {
  export DISCORD_SINK="$GCM_CHAT_SINK" CATCHALL_SINK="$GCM_CATCHALL_SINK"
}

teardown() {
  :
}

use_pactl_shim() {
  export SHIM_STATE="$BATS_TEST_TMPDIR/state"
  mkdir -p "$SHIM_STATE" "$BATS_TEST_TMPDIR/bin"
  printf '60\n' >"$SHIM_STATE/$GCM_CHAT_SINK"
  printf '40\n' >"$SHIM_STATE/$GCM_CATCHALL_SINK"
  cp "$REPO_ROOT/tests/fixtures/balance-pactl-shim.sh" "$BATS_TEST_TMPDIR/bin/pactl"
  chmod +x "$BATS_TEST_TMPDIR/bin/pactl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "chat shift moves STEP from catchall to chat" {
  set_volume_retry "$GCM_CHAT_SINK" 50
  set_volume_retry "$GCM_CATCHALL_SINK" 50
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
  run "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 0 ]
  wait_volume "$GCM_CHAT_SINK" 52
  wait_volume "$GCM_CATCHALL_SINK" 48
}

@test "game shift moves STEP from chat to catchall" {
  set_volume_retry "$GCM_CHAT_SINK" 50
  set_volume_retry "$GCM_CATCHALL_SINK" 50
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
  run "$GCM_BALANCE_SCRIPT" game
  [ "$status" -eq 0 ]
  wait_volume "$GCM_CHAT_SINK" 48
  wait_volume "$GCM_CATCHALL_SINK" 52
}

@test "reset restores both sinks to RESET_VOLUME" {
  set_volume_retry "$GCM_CHAT_SINK" 80
  set_volume_retry "$GCM_CATCHALL_SINK" 20
  wait_volume "$GCM_CHAT_SINK" 80
  wait_volume "$GCM_CATCHALL_SINK" 20
  run "$GCM_BALANCE_SCRIPT" reset
  [ "$status" -eq 0 ]
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
}

@test "shifts clamp at 0 and 100" {
  set_volume_retry "$GCM_CHAT_SINK" 1
  set_volume_retry "$GCM_CATCHALL_SINK" 99
  wait_volume "$GCM_CHAT_SINK" 1
  wait_volume "$GCM_CATCHALL_SINK" 99
  run "$GCM_BALANCE_SCRIPT" game
  [ "$status" -eq 0 ]
  wait_volume "$GCM_CHAT_SINK" 0
  wait_volume "$GCM_CATCHALL_SINK" 100
}

@test "STEP below 1 is rejected" {
  run env STEP=0 "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 1 ]
  [[ "$output" == *"STEP must be an integer percentage between 1 and 100"* ]]
}

@test "RESET_VOLUME above 100 is rejected" {
  run env RESET_VOLUME=101 "$GCM_BALANCE_SCRIPT" reset
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESET_VOLUME must be an integer percentage between 0 and 100"* ]]
}

@test "missing argument prints usage and fails" {
  run "$GCM_BALANCE_SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown argument prints usage and fails" {
  run "$GCM_BALANCE_SCRIPT" sideways
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing sink dies with a message" {
  run env DISCORD_SINK=gcm_missing_sink "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the volume of sink 'gcm_missing_sink'"* ]]
}

@test "shift preflights a missing second sink before changing chat" {
  set_volume_retry "$GCM_CHAT_SINK" 61
  run env CATCHALL_SINK=gcm_missing_sink "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the volume of sink 'gcm_missing_sink'"* ]]
  [ "$(sink_volume "$GCM_CHAT_SINK")" -eq 61 ]
}

@test "reset preflights a missing second sink before changing chat" {
  set_volume_retry "$GCM_CHAT_SINK" 61
  run env CATCHALL_SINK=gcm_missing_sink "$GCM_BALANCE_SCRIPT" reset
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the volume of sink 'gcm_missing_sink'"* ]]
  [ "$(sink_volume "$GCM_CHAT_SINK")" -eq 61 ]
}

@test "parallel hotkeys serialize complete shifts from independently set volumes" {
  use_pactl_shim
  export SHIM_READ_DELAY=0.15
  local pid count
  local -a hotkeys=()
  for ((count = 0; count < 8; count++)); do
    "$GCM_BALANCE_SCRIPT" chat &
    hotkeys+=("$!")
  done
  for pid in "${hotkeys[@]}"; do
    wait "$pid"
  done
  [ "$(<"$SHIM_STATE/$GCM_CHAT_SINK")" -eq 76 ]
  [ "$(<"$SHIM_STATE/$GCM_CATCHALL_SINK")" -eq 24 ]
}

@test "first write failure is not a partial update and does not attempt the second write" {
  use_pactl_shim
  run env SHIM_FAIL_SINK="$GCM_CHAT_SINK" "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot set the volume of sink '$GCM_CHAT_SINK'"* ]]
  [[ "$output" != *"partial update"* ]]
  [ "$(<"$SHIM_STATE/writes")" = "$GCM_CHAT_SINK" ]
}

@test "shift reports a partial update when the second write fails without rolling back" {
  use_pactl_shim
  run env SHIM_FAIL_SINK="$GCM_CATCHALL_SINK" SHIM_EXTERNAL_VOLUME=67 "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 2 ]
  [[ "$output" == *"partial update"*"$GCM_CHAT_SINK"*"$GCM_CATCHALL_SINK"* ]]
  [ "$(<"$SHIM_STATE/writes")" = "$GCM_CHAT_SINK"$'\n'"$GCM_CATCHALL_SINK" ]
  [ "$(<"$SHIM_STATE/$GCM_CHAT_SINK")" -eq 67 ]
  [ "$(<"$SHIM_STATE/$GCM_CATCHALL_SINK")" -eq 40 ]
}

@test "reset reports a partial update when the second write fails without rolling back" {
  use_pactl_shim
  run env SHIM_FAIL_SINK="$GCM_CATCHALL_SINK" "$GCM_BALANCE_SCRIPT" reset
  [ "$status" -eq 2 ]
  [[ "$output" == *"partial update"*"$GCM_CHAT_SINK"*"$GCM_CATCHALL_SINK"* ]]
  [ "$(<"$SHIM_STATE/writes")" = "$GCM_CHAT_SINK"$'\n'"$GCM_CATCHALL_SINK" ]
  [ "$(<"$SHIM_STATE/$GCM_CHAT_SINK")" -eq 50 ]
  [ "$(<"$SHIM_STATE/$GCM_CATCHALL_SINK")" -eq 40 ]
}

@test "reset parses leading zeroes in decimal" {
  use_pactl_shim
  run env RESET_VOLUME=008 "$GCM_BALANCE_SCRIPT" reset
  [ "$status" -eq 0 ]
  [ "$(<"$SHIM_STATE/$GCM_CHAT_SINK")" = 8 ]
  [ "$(<"$SHIM_STATE/$GCM_CATCHALL_SINK")" = 8 ]
}

@test "read error is not accepted even if pactl prints a percentage" {
  use_pactl_shim
  run env SHIM_FAIL_READ="$GCM_CATCHALL_SINK" "$GCM_BALANCE_SCRIPT" game
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read the volume of sink '$GCM_CATCHALL_SINK'"* ]]
  [ ! -e "$SHIM_STATE/writes" ]
}

@test "pactl runs in the C locale even under a different locale" {
  use_pactl_shim
  run env LC_ALL=POSIX SHIM_REQUIRE_C=1 "$GCM_BALANCE_SCRIPT" chat
  [ "$status" -eq 0 ]
}
