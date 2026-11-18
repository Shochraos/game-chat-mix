#!/usr/bin/env bats

# validate_config runs before the lock and before any pactl call, so these
# tests need no PipeWire session at all.

load 'test_helper'

setup_file() {
  :
}

teardown_file() {
  :
}

setup() {
  :
}

teardown() {
  :
}

@test "invalid CHAT_MATCH regex is rejected" {
  run env 'CHAT_MATCH=(' LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"CHAT_MATCH is not a valid extended regular expression: '('"* ]]
}

@test "INITIAL_VOLUME above 100 is rejected" {
  run env INITIAL_VOLUME=101 LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INITIAL_VOLUME must be an integer percentage between 0 and 100: '101'"* ]]
}

@test "non-numeric INITIAL_VOLUME is rejected" {
  run env INITIAL_VOLUME=abc LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INITIAL_VOLUME must be an integer percentage between 0 and 100: 'abc'"* ]]
}

@test "INITIAL_VOLUME that would overflow arithmetic is rejected" {
  run timeout 3 env INITIAL_VOLUME=18446744073709551616 LOCK_FILE="$BATS_TEST_TMPDIR/config.lock" bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"INITIAL_VOLUME must be an integer percentage between 0 and 100"* ]]
}

@test "negative EVENT_DEBOUNCE is rejected" {
  run env EVENT_DEBOUNCE=-1 LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"EVENT_DEBOUNCE must be a number of seconds: '-1'"* ]]
}

@test "RETRY_DELAY zero is rejected" {
  run env RETRY_DELAY=0 LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RETRY_DELAY must be a positive whole number of seconds: '0'"* ]]
}

@test "RETRY_DELAY_MAX below RETRY_DELAY is rejected" {
  run env RETRY_DELAY=2 RETRY_DELAY_MAX=1 LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"RETRY_DELAY_MAX must be a whole number of seconds not below RETRY_DELAY: '1'"* ]]
}

@test "identical sink names are rejected" {
  run env DISCORD_SINK=same CATCHALL_SINK=same LOCK_FILE=/tmp/gcm-config-test.lock bash "$GCM_MIX_SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"DISCORD_SINK and CATCHALL_SINK must differ: 'same'"* ]]
}

@test "daemon_stop reports clean shutdown under errexit" {
  GCM_RUN="$BATS_TEST_TMPDIR"
  bash -c 'trap "exit 0" TERM; touch "$1"; while :; do sleep 0.05; done' bash "$GCM_RUN/ready" &
  DAEMON_PID=$!
  printf '%s\n' "$DAEMON_PID" >"$GCM_RUN/daemon.pid"
  wait_until 4 test -f "$GCM_RUN/ready"

  daemon_stop
  [ ! -e "$GCM_RUN/daemon.pid" ]
}

@test "daemon_stop preserves a failing daemon exit status" {
  GCM_RUN="$BATS_TEST_TMPDIR"
  bash -c 'trap "exit 42" TERM; touch "$1"; while :; do sleep 0.05; done' bash "$GCM_RUN/ready" &
  DAEMON_PID=$!
  printf '%s\n' "$DAEMON_PID" >"$GCM_RUN/daemon.pid"
  wait_until 4 test -f "$GCM_RUN/ready"

  local stop_status=0
  daemon_stop || stop_status=$?
  [ "$stop_status" -eq 42 ]
  [ ! -e "$GCM_RUN/daemon.pid" ]
}

@test "daemon_stop distinguishes a TERM timeout from a daemon exit" {
  GCM_RUN="$BATS_TEST_TMPDIR"
  bash -c 'trap "" TERM; touch "$1"; exec sleep 60' bash "$GCM_RUN/ready" &
  DAEMON_PID=$!
  local stubborn_pid=$DAEMON_PID stop_status=0
  printf '%s\n' "$DAEMON_PID" >"$GCM_RUN/daemon.pid"
  wait_until 4 test -f "$GCM_RUN/ready"

  daemon_stop 1 || stop_status=$?
  [ "$stop_status" -eq 124 ]
  [ ! -d "/proc/$stubborn_pid" ]
  [ ! -e "$GCM_RUN/daemon.pid" ]
}
