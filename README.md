# Game-Chat-Mix

[![CI](https://github.com/Shochraos/game-chat-mix/actions/workflows/ci.yml/badge.svg)](https://github.com/Shochraos/game-chat-mix/actions/workflows/ci.yml)

Two bash scripts that implement the "Game-Chat-Mix" dial found on many gaming headsets, on top of PipeWire / PipeWire-Pulse.

> **AI Disclaimer**: The current implementation of both scripts, the Nix packaging and this README were written with AI assistance (Anthropic's Claude). Every change was verified against a live PipeWire session, but these scripts load and unload PulseAudio modules and change sink volumes on your machine. Read them before you run them, and see the licence for the absence of any warranty.

`gamechat_mix.sh` runs as a daemon. It creates two `module-remap-sink` sinks on top of your hardware output — one for the chat application, one for everything else — and continuously moves newly appearing streams into the catch-all sink. `gamechat_balance.sh` then shifts volume between the two sinks in fixed steps, so a single keybind pair moves the balance between game and voice audio without touching either application.

## How it works

- Both sinks are remaps of the same hardware sink, so they share one physical output.
- The master sink is resolved at runtime from `pactl get-default-sink`, and the daemon re-syncs whenever the PulseAudio server changes or a sink appears or disappears (device hotplug, default-sink switch). It never stacks a remap on top of one of its own remaps.
- Everything except the chat client's own streams is moved to the catch-all sink; the chat client is pointed at the chat sink once, inside the client itself.
- Both sinks start at 50% so there is headroom in both directions. A sink is only rebuilt when its master changes, and its volume is carried over when that happens. Unplugging a DAC does not throw away your balance, and restarting the daemon does not touch it.
- The daemon is self-healing: it waits with exponential backoff instead of exiting when no usable master sink exists yet, reconnects on its own if the `pactl` event stream ends, and recreates the sinks if something unloads them.
- Bursts of events are coalesced, so a game opening a dozen streams at once costs one routing pass rather than a dozen.
- Only one daemon runs at a time. It holds a `flock` for its whole lifetime, so a second copy — started by hand, by a second install method, or by a supervisor — logs a line and exits 0 instead of fighting over the remap sinks.
- **WirePlumber must be told not to restore the two sinks' volumes**, or it overrides the 50% start. See "WirePlumber volume restore" below; every installation method ships the opt-out.

## Tests

CI (`.github/workflows/ci.yml`) runs on every push to `main` and every pull request:

- **nix** — builds all three packages (shellcheck runs inside the builds), `nix flake check`, shfmt and nixfmt checks, and a bake proof for the plugin package: the daemon wrapper in the closure, the `@gamechat_mix@` substitution applied, and the sibling-script fallback present.
- **e2e** — runs the BATS suite in `tests/` against hermetic headless PipeWire sessions (own `XDG_RUNTIME_DIR`, stock WirePlumber config plus the volume-restore opt-out). It covers stream routing by client name, sink adoption and recreation, master changes, event-stream reconnect, the config validation paths, the flock single-instance guard, clean shutdown, and the standalone installer with a stubbed `systemctl`. Both jobs carry `timeout-minutes` bounds, and session logs upload on any non-success outcome (`!success()`), so a hung run fails with evidence instead of sitting out the default six-hour cap.

The whole suite runs locally and never touches the running desktop session:

```bash
nix develop -c bats tests/
```

## WirePlumber volume restore

WirePlumber persists and restores the volume of any `Audio/*` node that has no
device routes, which includes both remap sinks. Its state is keyed on
`media.name`, and `module-remap-sink` derives that from the description — so the
sinks are stored as `Audio/Sink:media.name:Discord\sinput` and
`All\sinput` in `~/.local/state/wireplumber/stream-properties`.

The effect is a bug: leave the chat sink at 0%, reboot, and WirePlumber restores
0% over the 50% the daemon just set, because the restore fires on node creation
and wins the race. The daemon already carries volumes across a master change by
itself, so WirePlumber's copy is redundant as well as harmful.

`wireplumber/99-gamechat-no-volume-restore.conf` turns it off for exactly these
two sinks, which disables both the save and the restore (WirePlumber gates them
on the same flag). Note the flag cannot be set through `sink_properties` —
`module-remap-sink` drops unknown keys — so it has to be a WirePlumber rule.

`standalone/install.sh` installs the file. With Nix, express the same rule
declaratively:

```nix
services.pipewire.wireplumber.extraConfig."99-gamechat-no-volume-restore" = {
  "stream.rules" = [
    {
      matches = [
        { "node.name" = "discord_sink"; }
        { "node.name" = "catchall_sink"; }
      ];
      actions.update-props."state.restore-props" = false;
    }
  ];
};
```

Stale entries already in `stream-properties` are harmless — with the rule in
place they are never read again.

## Configuration

Everything is an environment variable; there is nothing to edit in the scripts.

`gamechat_mix.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DISCORD_SINK` | `discord_sink` | Name of the chat sink |
| `CATCHALL_SINK` | `catchall_sink` | Name of the sink all other audio is moved to |
| `DISCORD_DESC` | `Discord` | Description the chat sink shows in mixers |
| `CATCHALL_DESC` | `All Other Audio` | Description the catch-all sink shows in mixers |
| `HW_SINK` | auto-detected | Master sink to remap. Set this to pin a specific output. |
| `CHAT_MATCH` | `discord\|webrtc` | Lower-case extended regex; a stream whose application, client, binary or node name matches goes to the chat sink |
| `INITIAL_VOLUME` | `50` | Percentage a newly created sink starts at |
| `EVENT_DEBOUNCE` | `0.05` | Seconds to keep collecting events before acting on a burst |
| `RETRY_DELAY` | `1` | Seconds before the first retry; doubles on repeated failure |
| `RETRY_DELAY_MAX` | `30` | Ceiling for that backoff |
| `LOCK_FILE` | `$XDG_RUNTIME_DIR/gamechat_mix.lock` | Single-instance lock. A second daemon holding no lock exits immediately; point two daemons at different files only if they also drive different sinks. |

`gamechat_balance.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `DISCORD_SINK` | `discord_sink` | Name of the chat sink |
| `CATCHALL_SINK` | `catchall_sink` | Name of the sink all other audio is moved to |
| `STEP` | `2` | Percentage points moved per invocation |
| `RESET_VOLUME` | `50` | Percentage both sinks are set to by `reset` |

The two scripts share `DISCORD_SINK` and `CATCHALL_SINK`, so the daemon and the
keybinds cannot end up pointing at different sinks. Both reject an invalid value
with a message instead of misbehaving.

List candidate sink names with `pactl list short sinks`.

## Installation

Each installation method lives in its own subfolder. The two scripts live
**once**, inside the `dms/` plugin directory; every method references them
rather than copying them.

| Method | Folder | What it adds |
| --- | --- | --- |
| Nix flake | `nix/` | `packages.<system>.gamechat_mix`, `gamechat_balance` and the self-contained `dms_plugin` |
| Standalone | `standalone/` | both scripts in `~/.local/bin` plus a systemd user unit |
| DankMaterialShell plugin | `dms/` | a DankBar mix slider plus the routing scripts it runs |

The methods are independent but not exclusive: the DMS plugin can either manage
the daemon itself or leave it to the systemd unit installed by one of the other
two. The daemon takes a `flock` either way, so a second copy exits instead of
fighting over the remap sinks.

### Nix flake

Add the input:

```nix
{
  inputs.game-chat-mix = {
    url = "github:Shochraos/game-chat-mix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

The flake exposes `packages.<system>.gamechat_mix` (the daemon, also `default`), `packages.<system>.gamechat_balance` (the keybind helper) and `packages.<system>.dms_plugin`, a DankMaterialShell plugin whose closure carries the daemon.

NixOS module — install the helper and enable PipeWire-Pulse:

```nix
{ inputs, pkgs, ... }:
{
  services.pipewire.pulse.enable = true;

  environment.systemPackages = [
    inputs.game-chat-mix.packages.${pkgs.stdenv.hostPlatform.system}.gamechat_balance
  ];
}
```

Home Manager — run the daemon for the graphical session:

```nix
{ inputs, lib, pkgs, ... }:
{
  systemd.user.services.gamechat-mix = {
    Unit = {
      Description = "Dynamically sorts audio streams into sinks to independently manage volume";
      PartOf = [ "graphical-session.target" ];
      Wants = [ "pipewire-pulse.service" ];
      After = [ "pipewire-pulse.service" ];
    };

    Service = {
      Type = "simple";
      ExecStart = lib.getExe inputs.game-chat-mix.packages.${pkgs.stdenv.hostPlatform.system}.gamechat_mix;
      Restart = "always";
      RestartSec = 5;
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
```

Then bind `gamechat_balance game`, `gamechat_balance chat` and `gamechat_balance reset` to hotkeys in your compositor or desktop environment.

Without a flake, `nix run github:Shochraos/game-chat-mix` starts the daemon and `nix run github:Shochraos/game-chat-mix#gamechat_balance -- chat` shifts the balance.

### Standalone

Requirements: `bash`, PipeWire with PipeWire-Pulse running (`pactl`), `gawk`,
`coreutils`, `util-linux`.

```bash
git clone https://github.com/Shochraos/game-chat-mix.git
cd game-chat-mix
./standalone/install.sh
```

See [`standalone/README.md`](standalone/README.md) for the destinations it
writes to and how to remove it again.

### DankMaterialShell plugin

A composite [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
plugin: a DankBar pill showing the current mix, a popout slider that moves the
balance by dragging, and an `IpcHandler` so `dms ipc call gamechat …` works.

The plugin directory carries the routing scripts, so every install — registry,
manual copy, plain Nix source — is self-contained: the plugin starts and
supervises the daemon itself (`manageDaemon` defaults to `true`), with no
systemd unit and no PATH entry. The `dms_plugin` package is the hermetic Nix
variant: it bakes the pinned `gamechat_mix` wrapper into the plugin.

```nix
programs.dank-material-shell.plugins.gamechatMix = {
  enable = true;
  src = inputs.game-chat-mix.packages.${pkgs.stdenv.hostPlatform.system}.dms_plugin;
};
```

See [`dms/README.md`](dms/README.md) for installation and settings.

## Layout

```
dms/          DankMaterialShell composite plugin; both scripts live here as the single source
wireplumber/  the volume-restore opt-out, shared by every install method
nix/          flake package definitions
standalone/   systemd user unit + installer for a non-Nix machine
```

- `dms/gamechat_mix.sh`: creates the two remap sinks on the current hardware sink and keeps routing new streams into the catch-all sink. Single-instance, guarded by `flock`.
- `dms/gamechat_balance.sh`: takes `game`, `chat` or `reset` and moves the volume balance between the two sinks by `STEP` percentage points per invocation, clamped to 0–100%.

## Limitations

- Only Discord and WebRTC are recognised as chat applications out of the box; widen `CHAT_MATCH` to add more. The filter matches application, client, binary and node names.
- The chat client's output device still has to be selected manually inside the client.
- Both sinks sit at 50% by default so the balance has headroom in both directions, which costs a little absolute volume.

## Development

`nix develop` provides `shellcheck`, `shfmt`, `nixfmt` and `pactl`. `nix build` runs shellcheck over both scripts, so it doubles as the lint gate; `nix fmt` formats the Nix files and `shfmt -d` checks the shell ones against the 2-space indent pinned in `.editorconfig`.

## License

[MIT](LICENSE) © 2026 Shochraos
