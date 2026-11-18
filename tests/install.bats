#!/usr/bin/env bats

load 'test_helper'

SB="" ; HOME_S="" ; SHIM_LOG="" ; SHIM_DIR="" ; MIN_DIR="" ; MIN_NOPACTL_DIR="" ; MANAGED_PID=""

sandbox_setup() {
  SB="$GCM_BASE/install"
  rm -rf "$SB"
  HOME_S="$SB/home"
  SHIM_DIR="$SB/shim"
  SHIM_LOG="$SB/systemctl.log"
  MIN_DIR="$SB/min"
  MIN_NOPACTL_DIR="$SB/min-nopactl"
  mkdir -p "$HOME_S/.config" "$SHIM_DIR" "$MIN_DIR" "$MIN_NOPACTL_DIR"

  cp "$REPO_ROOT/tests/fixtures/systemctl-shim.sh" "$SHIM_DIR/systemctl"
  chmod +x "$SHIM_DIR/systemctl"

  local tool
  for tool in bash install pactl dirname mktemp rm; do
    ln -sf "$(command -v "$tool")" "$MIN_DIR/$tool"
  done
  for tool in bash install dirname; do
    ln -sf "$(command -v "$tool")" "$MIN_NOPACTL_DIR/$tool"
  done
}

setup() {
  session_reset
  sandbox_setup
}

teardown() {
  daemon_stop
  if [ -n "$MANAGED_PID" ]; then
    DAEMON_PID="$MANAGED_PID"
    daemon_stop
  fi
  session_reset
}

install_default() {
  run env -u BIN_DIR -u UNIT_DIR -u WIREPLUMBER_DIR PATH="$SHIM_DIR:$MIN_DIR" HOME="$HOME_S" \
    XDG_CONFIG_HOME="$HOME_S/.config" SHIM_LOG_FILE="$SHIM_LOG" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 0 ]
}

start_installed_daemon() {
  local unit="$HOME_S/.config/systemd/user/gamechat-mix.service" command environment
  command=$(grep '^ExecStart=' "$unit")
  environment=$(grep '^Environment=' "$unit")
  command=${command#ExecStart=:/usr/bin/env bash \"}
  command=${command%\"}
  env -u LOCK_FILE -u GAMECHAT_WAIT_FOR_LOCK HW_SINK="$GCM_MASTER" "${environment#Environment=}" bash "$command" \
    >"$GCM_LOGS/installed-daemon.log" 2>&1 3>&- &
  MANAGED_PID=$!
}

@test "install.sh installs scripts, unit and wireplumber conf, then starts the unit" {
  install_default

  [ -x "$HOME_S/.local/bin/gamechat_mix" ]
  [ -x "$HOME_S/.local/bin/gamechat_balance" ]
  cmp -s "$HOME_S/.local/bin/gamechat_mix" "$REPO_ROOT/dms/gamechat_mix.sh"
  cmp -s "$HOME_S/.local/bin/gamechat_balance" "$REPO_ROOT/dms/gamechat_balance.sh"

  local unit="$HOME_S/.config/systemd/user/gamechat-mix.service"
  grep -Fxq "ExecStart=:/usr/bin/env bash \"$HOME_S/.local/bin/gamechat_mix\"" "$unit"
  grep -Fxq 'Environment=GAMECHAT_WAIT_FOR_LOCK=1' "$unit"
  grep -Fxq 'Restart=on-failure' "$unit"
  [ -f "$HOME_S/.config/wireplumber/wireplumber.conf.d/99-gamechat-no-volume-restore.conf" ]

  grep -Fqx -- '--user daemon-reload' "$SHIM_LOG"
  grep -Fqx -- '--user enable gamechat-mix.service' "$SHIM_LOG"
  grep -Fqx -- '--user restart gamechat-mix.service' "$SHIM_LOG"
  grep -Fqx -- '--user restart wireplumber.service' "$SHIM_LOG"
}

@test "custom BIN_DIR is encoded literally in the installed unit" {
  local custom_bin="$SB/"'mix %h $HOME "quote" \path;#'
  local unit="$SB/units/gamechat-mix.service"
  run env PATH="$SHIM_DIR:$MIN_DIR" HOME="$HOME_S" BIN_DIR="$custom_bin" UNIT_DIR="$SB/units" \
    XDG_CONFIG_HOME="$HOME_S/.config" SHIM_LOG_FILE="$SHIM_LOG" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 0 ]
  [ -x "$custom_bin/gamechat_mix" ]
  [ -x "$custom_bin/gamechat_balance" ]
  [ ! -e "$HOME_S/.local/bin/gamechat_mix" ]
  grep -Fxq "ExecStart=:/usr/bin/env bash \"$SB/"'mix %%h $HOME \"quote\" \\path;#/gamechat_mix"' "$unit"
}

@test "unsupported BIN_DIR fails before creating any installed files" {
  local custom_bin="$SB/"$'bad\npath'
  run env PATH="$SHIM_DIR:$MIN_DIR" HOME="$HOME_S" BIN_DIR="$custom_bin" \
    XDG_CONFIG_HOME="$HOME_S/.config" SHIM_LOG_FILE="$SHIM_LOG" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *BIN_DIR* ]]
  [ ! -e "$custom_bin" ]
  [ ! -e "$HOME_S/.config/systemd" ]
  [ ! -e "$HOME_S/.config/wireplumber" ]
  [ ! -e "$SHIM_LOG" ]
}

@test "when the installed managed daemon starts first a manual copy exits cleanly" {
  install_default
  start_installed_daemon
  wait_sink_exists "$GCM_CHAT_SINK"
  wait_sink_exists "$GCM_CATCHALL_SINK"
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
  run env -u LOCK_FILE -u GAMECHAT_WAIT_FOR_LOCK HW_SINK="$GCM_MASTER" timeout 3 "$GCM_MIX_SCRIPT"
  [ "$status" -eq 0 ]
  kill -0 "$MANAGED_PID"
  probe_start 'Discord Installed First'
  wait_stream_on 'Discord Installed First' "$GCM_CHAT_SINK"
}

@test "when the manual daemon starts first the installed managed daemon waits and takes over" {
  install_default
  daemon_start
  local former_owner="$DAEMON_PID"
  wait_sink_exists "$GCM_CHAT_SINK"
  wait_sink_exists "$GCM_CATCHALL_SINK"
  start_installed_daemon
  wait_until 3 grep -Fq 'waiting for lock' "$GCM_LOGS/installed-daemon.log"
  kill -0 "$MANAGED_PID"
  daemon_stop
  [ ! -d "/proc/$former_owner" ]
  probe_start 'Game After Lock Handover'
  wait_stream_on 'Game After Lock Handover' "$GCM_CATCHALL_SINK"
  kill -0 "$MANAGED_PID"
}

@test "install.sh without systemctl skips the unit and still succeeds" {
  run env PATH="$MIN_DIR" HOME="$HOME_S" \
    XDG_CONFIG_HOME="$HOME_S/.config" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME_S/.config/systemd/user/gamechat-mix.service" ]
  [ -x "$HOME_S/.local/bin/gamechat_mix" ]
  [[ "$output" == *"systemctl not found"* ]]
}

@test "install.sh without pactl fails cleanly" {
  run env PATH="$MIN_NOPACTL_DIR" HOME="$HOME_S" \
    XDG_CONFIG_HOME="$HOME_S/.config" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required command 'pactl'"* ]]
}
