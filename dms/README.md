# DuxShell (DankMaterialShell) plugin

A composite [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
plugin (`id = gamechatMix`, requires DMS >= 1.5.0) with two surfaces:

- **Widget:** a DankBar pill showing Game / Chat and a popout with one slider.
  Drag the slider or use the arrow keys. Left favors Game, right favors Chat.
  Tab to Reset and press Space or Enter to set both to 50%.
- **Daemon:** an optional supervisor for `gamechat_mix`, plus an `IpcHandler`
  so `dms ipc call gamechat …` works from compositor keybinds.

The slider writes directly to PipeWire. Both labels report their actual sink
volume, even when only one sink is available. When a sink is missing, the
slider has no thumb and the popout names the missing sink after a short wait.

![Offscreen preview of the mix popout with sample Game and Chat volumes](../assets/screenshot.png)

## Installation

Every install of the plugin carries the routing scripts with it — the daemon
is not a separate installation. The only choice is whether the daemon runs the
Nix-pinned wrapper or the sibling script next to the QML:

**Nix, hermetic:** the `dms_plugin` package bakes the pinned `gamechat_mix`
wrapper into the QML:

```nix
programs.dank-material-shell.plugins.gamechatMix = {
  enable = true;
  src = inputs.game-chat-mix.packages.${pkgs.stdenv.hostPlatform.system}.dms_plugin;
};
```

**Nix, plain source** — or the DMS plugin registry, or a manual copy:

```nix
programs.dank-material-shell.plugins.gamechatMix = {
  enable = true;
  src = "${inputs.game-chat-mix}/dms";
};
```

```bash
git clone https://github.com/Shochraos/game-chat-mix.git
cp -r game-chat-mix/dms ~/.config/DankMaterialShell/plugins/gamechatMix
```

Here the daemon is the sibling `gamechat_mix.sh`, run on whatever `bash`,
`gawk`, `flock` and `pactl` PATH provides — on NixOS that is your generation's
system environment (keep `pulseaudio` in `systemPackages` for `pactl`; `gawk`
and `util-linux` are in the default environment).

`manageDaemon` defaults to `true` in every case: the plugin starts and
supervises the daemon itself, no systemd user unit needed. Set
`settings.manageDaemon = false` only when something else already runs it.

In **Settings → Plugins**, select **Scan for Plugins** and enable
**Game / Chat Mix**. Add the widget in **Settings → Dank Bar → Widgets**.
If the popout reports missing sinks, use **Open Plugins** to check their names.
For missing audio output, check **Settings → System → Audio**.

Either way the WirePlumber volume-restore opt-out is still required, or the
sinks come back at their last volume rather than 50% — see "WirePlumber volume
restore" in the [top-level README](../README.md).

## Settings

| Key | Default | Meaning |
| --- | --- | --- |
| `manageDaemon` | `true` | Start and supervise `gamechat_mix` from the shell. Set `false` when a systemd user unit already runs it. |
| `mixCommand` | *(empty)* | The Nix-pinned wrapper if packaged, otherwise the sibling `gamechat_mix.sh`. Set a command to override this in managed mode. |
| `gameSink` | *(automatic)* | Lookup name. Defaults to the shell's `CATCHALL_SINK` in managed mode if set; otherwise `catchall_sink`. |
| `chatSink` | *(automatic)* | Lookup name. Defaults to the shell's `DISCORD_SINK` in managed mode if set; otherwise `discord_sink`. |
| `step` | `2` | Percentage points per `game` or `chat` IPC call. Match `STEP` where you run `gamechat_balance`. |

For an override, use an executable path or a name on `PATH`. Quote a path or
argument containing spaces, for example `"/home/me/My Scripts/gamechat_mix"`.
The command is not run in a shell: there is no variable, `~`, or glob expansion.

The managed daemon waits for the routing lock and takes over if the other
instance exits. The plugin retries a launch failure or unsuccessful exit after
5 seconds. A clean exit does not restart. In external mode, the plugin never
launches the daemon; check the service that owns it if the sinks are missing.

### Custom sink names

The plugin settings look up existing sink names; they do not rename sinks.
With a managed daemon, leave them blank or match `CATCHALL_SINK` and
`DISCORD_SINK` in the shell's environment. A mismatch blocks managed startup
and mix writes. If you use a custom command, it must honor those variables.
For an external daemon, enter the names configured in that service. Use two
distinct names containing only letters, digits, dots, underscores or hyphens.

To rename remaps, stop the routing owner first and remove the old remaps before
starting it with new names. Restarting your audio session after stopping the
owner also clears the old remaps, but interrupts audio. Update the WirePlumber
`node.name` matches and any `gamechat_balance` environment to use the same names.
Change a managed daemon's environment in the shell launcher, then relaunch the
shell. Editing the plugin's lookup names alone cannot migrate existing remaps.

## IPC

| Call | Equivalent to |
| --- | --- |
| `dms ipc call gamechat game` | `gamechat_balance game` |
| `dms ipc call gamechat chat` | `gamechat_balance chat` |
| `dms ipc call gamechat reset` | `gamechat_balance reset` |
| `dms ipc call gamechat setMix <chat percent>` | — |
| `dms ipc call gamechat status` | — |

`status` returns `{"game": …, "chat": …, "managedDaemon": …}` with `-1` for
each unavailable volume. The mutating calls return the same shape on success or
`SINKS_UNAVAILABLE` when either sink cannot be used. `setMix` returns
`INVALID_PERCENT` when its argument cannot be parsed as an integer.

## Slider semantics

The slider shows Chat's volume on a 0–100 scale. Moving it sets Game to
`100 − Chat`. If you change just one sink in an audio mixer, the labels still
show both actual volumes. The next slider adjustment restores a total of 100.
The `game` and `chat` IPC calls instead shift each current volume by `step`,
clamping each to 0–100. `setMix` sets a complementary pair; `reset` sets 50/50.
