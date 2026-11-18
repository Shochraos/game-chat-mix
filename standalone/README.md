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

`BIN_DIR` must be an absolute path without control characters or `..` path
components. Spaces are supported: for example,
`BIN_DIR="$HOME/My Tools/bin" ./standalone/install.sh`. The installed unit uses
that directory directly, regardless of `PATH`. Re-running the installer restarts
the unit so it picks up the new executable path.

Afterwards:

1. Select the chat sink ("Discord") as the output device inside your chat client.
2. Bind `gamechat_balance game`, `gamechat_balance chat` and
   `gamechat_balance reset` to hotkeys in your compositor or desktop environment.

The daemon holds a `flock` on `$XDG_RUNTIME_DIR/gamechat_mix.lock`. If the unit
starts while a copy already owns the lock, it waits until that copy exits. A
copy started by hand while the lock is held exits successfully without touching
the sinks. Systemd restarts the daemon only on failure.

The hotkey helper serializes its own invocations with a separate per-user lock,
`$XDG_RUNTIME_DIR/gamechat_balance.lock` (or `gamechat-mix/gamechat_balance.lock`
under the user cache directory if `XDG_RUNTIME_DIR` is unset). All three commands
check both sinks before writing. If the first write succeeds and the second
fails, the helper reports a partial update and exits with status 2 instead of
rolling back and potentially overwriting a change from another mixer. Other
handled failures exit with status 1.

To remove it again, substitute your destination overrides for the default paths
below if you used any:

```bash
systemctl --user disable --now gamechat-mix.service
rm -f ~/.config/systemd/user/gamechat-mix.service
rm -f ~/.local/bin/gamechat_mix ~/.local/bin/gamechat_balance
rm -f ~/.config/wireplumber/wireplumber.conf.d/99-gamechat-no-volume-restore.conf
systemctl --user daemon-reload
systemctl --user restart wireplumber.service
```
