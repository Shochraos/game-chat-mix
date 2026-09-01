#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  session_start
  load_remap "$GCM_CHAT_SINK" "$GCM_MASTER" "Discord"
  load_remap "$GCM_CATCHALL_SINK" "$GCM_MASTER" "All Other Audio"
}

setup() {
  :
}

teardown() {
  :
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
