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

`gamechat_mix` must be reachable, either already running (see
[`../standalone/README.md`](../standalone/README.md) or the flake) or on `PATH`
so the plugin can start it itself.

```bash
git clone https://github.com/Shochraos/game-chat-mix.git
cp -r game-chat-mix/dms ~/.config/DankMaterialShell/plugins/gamechatMix
```

Then Settings → Plugins → **Scan for Plugins**, enable **Game / Chat Mix**, and
add the widget via Settings → Appearance → DankBar Layout.

With Nix and home-manager, point the DMS module at the `dms/` subdirectory
instead of copying:

```nix
programs.dank-material-shell.plugins.gamechatMix = {
  enable = true;
  src = "${inputs.game-chat-mix}/dms";
  settings.manageDaemon = false;
};
```

Either way the WirePlumber volume-restore opt-out is still required, or the
sinks come back at their last volume rather than 50% — see "WirePlumber volume
restore" in the [top-level README](../README.md).

## Settings

| Key | Default | Meaning |
| --- | --- | --- |
| `manageDaemon` | `true` | Start and supervise `gamechat_mix` from the shell. Set `false` when a systemd user unit already runs it. |
| `mixCommand` | `gamechat_mix` | Command used when the daemon is managed by the shell, resolved from `PATH`. |
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
