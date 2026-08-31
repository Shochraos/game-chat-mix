# DankMaterialShell plugin

A composite [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
plugin (`id = gamechatMix`, requires DMS >= 1.5.0) with two surfaces:

- **widget** — a DankBar pill showing `game / chat`, and a popout carrying the
  mix slider. Game is on the left, chat on the right; dragging moves the
  balance.
- **daemon** — an optional supervisor for `gamechat_mix`, plus an `IpcHandler`
  so `dms ipc call gamechat …` works from compositor keybinds.

The slider writes the two PipeWire node volumes directly, so dragging costs no
process spawn, and the displayed value is read straight off the nodes — pressing
the `gamechat_balance` keybinds visibly moves the slider.

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

Then Settings → Plugins → **Scan for Plugins**, enable **Game / Chat Mix**, and
add the widget via Settings → Appearance → DankBar Layout.

Either way the WirePlumber volume-restore opt-out is still required, or the
sinks come back at their last volume rather than 50% — see "WirePlumber volume
restore" in the [top-level README](../README.md).

## Settings

| Key | Default | Meaning |
| --- | --- | --- |
| `manageDaemon` | `true` | Start and supervise `gamechat_mix` from the shell. Set `false` when a systemd user unit already runs it. |
| `mixCommand` | *(empty)* | Command used when the daemon is managed by the shell. Empty picks the Nix-pinned wrapper when present, else the sibling `gamechat_mix.sh` next to the QML. |
| `gameSink` | `catchall_sink` | Must match `CATCHALL_SINK` in the daemon's environment. |
| `chatSink` | `discord_sink` | Must match `DISCORD_SINK` in the daemon's environment. |
| `step` | `2` | Percentage points moved per `dms ipc call gamechat game\|chat`. Match `STEP` so both surfaces agree. |

Running the daemon twice is safe either way — it takes a `flock`, so whichever
copy starts second exits immediately. The plugin only retries a **failed** exit
(after 5 s); a clean exit means another copy already owns the sinks, so it is
deliberately left alone rather than respawned in a loop.

## IPC

| Call | Equivalent to |
| --- | --- |
| `dms ipc call gamechat game` | `gamechat_balance game` |
| `dms ipc call gamechat chat` | `gamechat_balance chat` |
| `dms ipc call gamechat reset` | `gamechat_balance reset` |
| `dms ipc call gamechat setMix <chat percent>` | — |
| `dms ipc call gamechat status` | — |

Each returns `{"game": …, "chat": …, "managedDaemon": …}`, or
`SINKS_UNAVAILABLE` when the remap sinks are not up yet.

## Slider semantics

The slider position **is** the chat sink's volume; the game sink gets
`100 − position`. Both sinks start at 50 and every `gamechat_balance` shift is
equal and opposite, so the pair normally sums to 100 and the slider and the
keybinds agree by construction.

If you move one of the two sinks on its own — from `pavucontrol`, or from DMS's
own audio mixer — the pair stops summing to 100. The slider keeps showing the
chat volume, and the **first drag re-normalises the pair** back to summing 100.
That is deliberate: the widget owns one number, not two.
