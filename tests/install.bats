#!/usr/bin/env bats

load 'test_helper'

SB="" ; HOME_S="" ; SHIM_LOG="" ; SHIM_DIR="" ; MIN_DIR="" ; MIN_NOPACTL_DIR=""

sandbox_setup() {
  SB="$GCM_BASE/install"
  rm -rf "$SB"
  HOME_S="$SB/home"
  SHIM_DIR="$SB/shim"
  SHIM_LOG="$SB/systemctl.log"
  MIN_DIR="$SB/min"
  MIN_NOPACTL_DIR="$SB/min-nopactl"
  mkdir -p "$HOME_S/.config" "$SHIM_DIR" "$MIN_DIR" "$MIN_NOPACTL_DIR"

  # Shim copied verbatim from the fixture so no heredoc quoting can mangle
  # it; the log path travels through the environment instead.
  cp "$REPO_ROOT/tests/fixtures/systemctl-shim.sh" "$SHIM_DIR/systemctl"
  chmod +x "$SHIM_DIR/systemctl"

  # Restricted PATHs so the host's real systemctl can never be reached.
  local tool
  for tool in bash install pactl dirname; do
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
  session_reset
}

@test "install.sh installs scripts, unit and wireplumber conf, then starts the unit" {
  run env PATH="$SHIM_DIR:$MIN_DIR" HOME="$HOME_S" \
    XDG_CONFIG_HOME="$HOME_S/.config" SHIM_LOG_FILE="$SHIM_LOG" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 0 ]

  [ -x "$HOME_S/.local/bin/gamechat_mix" ]
  [ -x "$HOME_S/.local/bin/gamechat_balance" ]
  cmp -s "$HOME_S/.local/bin/gamechat_mix" "$REPO_ROOT/dms/gamechat_mix.sh"
  cmp -s "$HOME_S/.local/bin/gamechat_balance" "$REPO_ROOT/dms/gamechat_balance.sh"

  [ -f "$HOME_S/.config/systemd/user/gamechat-mix.service" ]
  [ -f "$HOME_S/.config/wireplumber/wireplumber.conf.d/99-gamechat-no-volume-restore.conf" ]

  grep -Fqx -- '--user daemon-reload' "$SHIM_LOG"
  grep -Fqx -- '--user enable --now gamechat-mix.service' "$SHIM_LOG"
  grep -Fqx -- '--user restart wireplumber.service' "$SHIM_LOG"
}

@test "installed gamechat_mix runs the fresh-start scenario" {
  run env PATH="$SHIM_DIR:$MIN_DIR" HOME="$HOME_S" \
    XDG_CONFIG_HOME="$HOME_S/.config" SHIM_LOG_FILE="$SHIM_LOG" \
    bash "$REPO_ROOT/standalone/install.sh"
  [ "$status" -eq 0 ]

  GCM_MIX_SCRIPT="$HOME_S/.local/bin/gamechat_mix"
  daemon_start
  wait_sink_exists "$GCM_CHAT_SINK"
  wait_sink_exists "$GCM_CATCHALL_SINK"
  wait_volume "$GCM_CHAT_SINK" 50
  wait_volume "$GCM_CATCHALL_SINK" 50
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
