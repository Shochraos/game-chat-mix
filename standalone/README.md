# Standalone installation

For a machine without Nix. Installs both scripts into `~/.local/bin` under the
names `gamechat_mix` and `gamechat_balance` (no `.sh`, matching the Nix package
binaries), then installs and starts a systemd user unit for the daemon.

Requirements: `bash`, `gawk`, `coreutils`, `util-linux` (for `flock`), and
PipeWire with PipeWire-Pulse running so `pactl` works.

```bash
git clone https://github.com/Shochraos/game-chat-mix.git
cd game-chat-mix
./standalone/install.sh
```

It also installs `wireplumber/99-gamechat-no-volume-restore.conf` and restarts
WirePlumber, without which the sinks come back at their last volume instead of
50% — see the "WirePlumber volume restore" section of the top-level README.

Three environment variables override the destinations:

| Variable | Default |
| --- | --- |
| `BIN_DIR` | `~/.local/bin` |
| `UNIT_DIR` | `$XDG_CONFIG_HOME/systemd/user` |
| `WIREPLUMBER_DIR` | `$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d` |

Afterwards:

1. Select the chat sink ("Discord") as the output device inside your chat client.
2. Bind `gamechat_balance game`, `gamechat_balance chat` and
   `gamechat_balance reset` to hotkeys in your compositor or desktop environment.

The daemon holds a `flock` on `$XDG_RUNTIME_DIR/gamechat_mix.lock`, so a second
copy started by hand exits immediately instead of fighting the unit over the
remap sinks.

To remove it again:

```bash
systemctl --user disable --now gamechat-mix.service
rm -f ~/.config/systemd/user/gamechat-mix.service
rm -f ~/.local/bin/gamechat_mix ~/.local/bin/gamechat_balance
rm -f ~/.config/wireplumber/wireplumber.conf.d/99-gamechat-no-volume-restore.conf
systemctl --user daemon-reload
systemctl --user restart wireplumber.service
```
