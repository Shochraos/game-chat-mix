#!/usr/bin/env bash

set -euo pipefail

BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"
UNIT_DIR="${UNIT_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user}"
WIREPLUMBER_DIR="${WIREPLUMBER_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/wireplumber/wireplumber.conf.d}"

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$here")

log() {
  printf 'gamechat-install: %s\n' "$*" >&2
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command '${1}'"
    exit 1
  }
}

require install
require pactl

install -Dm755 "${root}/dms/gamechat_mix.sh" "${BIN_DIR}/gamechat_mix"
install -Dm755 "${root}/dms/gamechat_balance.sh" "${BIN_DIR}/gamechat_balance"
log "installed gamechat_mix and gamechat_balance into '${BIN_DIR}'"

case ":${PATH}:" in
*":${BIN_DIR}:"*) ;;
*) log "warning: '${BIN_DIR}' is not on PATH; add it so the keybind helper resolves" ;;
esac

install -Dm644 "${root}/wireplumber/99-gamechat-no-volume-restore.conf" \
  "${WIREPLUMBER_DIR}/99-gamechat-no-volume-restore.conf"
log "installed the WirePlumber volume-restore opt-out into '${WIREPLUMBER_DIR}'"

if ! command -v systemctl >/dev/null 2>&1; then
  log "systemctl not found; start the daemon yourself with '${BIN_DIR}/gamechat_mix &',"
  log "and restart WirePlumber so the volume-restore opt-out applies"
  exit 0
fi

install -Dm644 "${here}/gamechat-mix.service" "${UNIT_DIR}/gamechat-mix.service"
log "installed gamechat-mix.service into '${UNIT_DIR}'"

systemctl --user daemon-reload
systemctl --user enable --now gamechat-mix.service
systemctl --user restart wireplumber.service
log "gamechat-mix.service enabled and started"

log "next: select the 'Discord' sink as the output device inside your chat client,"
log "      then bind 'gamechat_balance game|chat|reset' to hotkeys."
