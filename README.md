# Game-Chat-Mix

Two bash scripts that implement the "Game-Chat-Mix" dial found on many gaming headsets, on top of PipeWire / PipeWire-Pulse.

> **AI Disclaimer**: The current implementation of both scripts, the Nix packaging and this README were written with AI assistance (Anthropic's Claude). Every change was verified against a live PipeWire session, but these scripts load and unload PulseAudio modules and change sink volumes on your machine — read them before you run them, and see the licence for the absence of any warranty.

`gamechat_mix.sh` runs as a daemon. It creates two `module-remap-sink` sinks on top of your hardware output — one for the chat application, one for everything else — and continuously moves newly appearing streams into the catch-all sink. `gamechat_balance.sh` then shifts volume between the two sinks in fixed steps, so a single keybind pair moves the balance between game and voice audio without touching either application.

## How it works

- Both sinks are remaps of the same hardware sink, so they share one physical output.
- The master sink is resolved at runtime from `pactl get-default-sink`, and the daemon re-syncs whenever the PulseAudio server changes or a sink appears or disappears (device hotplug, default-sink switch). It never stacks a remap on top of one of its own remaps.
- Everything except the chat client's own streams is moved to the catch-all sink; the chat client is pointed at the chat sink once, inside the client itself.
- Both sinks start at 50% so there is headroom in both directions. A sink is only rebuilt when its master changes, and its volume is carried over when that happens — unplugging a DAC does not throw away your balance, and restarting the daemon does not touch it.
- The daemon is self-healing: it waits with exponential backoff instead of exiting when no usable master sink exists yet, reconnects on its own if the `pactl` event stream ends, and recreates the sinks if something unloads them.
- Bursts of events are coalesced, so a game opening a dozen streams at once costs one routing pass rather than a dozen.

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

## Usage as a Nix flake

Add the input:

```nix
{
  inputs.game-chat-mix = {
    url = "github:Shochraos/game-chat-mix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

The flake exposes `packages.<system>.gamechat_mix` (the daemon, also `default`) and `packages.<system>.gamechat_balance` (the keybind helper).

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

## Usage without Nix

Requirements: `bash`, PipeWire with PipeWire-Pulse running (`pactl`), `gawk`, `coreutils`.

1. Clone the repository:

   ```bash
   git clone https://github.com/Shochraos/game-chat-mix.git
   cd game-chat-mix
   ```

2. Start the daemon and check that both sinks appear:

   ```bash
   ./gamechat_mix.sh &
   pactl list short sinks
   ```

3. Select the chat sink ("Discord") as the output device inside your chat client.

4. Keep the daemon running across logins with a systemd user unit at `~/.config/systemd/user/gamechat-mix.service`:

   ```ini
   [Unit]
   Description=Dynamically sorts audio streams into sinks to independently manage volume
   PartOf=graphical-session.target
   Wants=pipewire-pulse.service
   After=pipewire-pulse.service

   [Service]
   Type=simple
   ExecStart=%h/game-chat-mix/gamechat_mix.sh
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=graphical-session.target
   ```

   ```bash
   systemctl --user daemon-reload
   systemctl --user enable --now gamechat-mix.service
   ```

5. Bind the balance verbs to hotkeys in your desktop environment. `./gamechat_balance.sh game` gives more game and less chat, `./gamechat_balance.sh chat` does the reverse, and `./gamechat_balance.sh reset` puts both sinks back to 50%.

## Development

`nix develop` provides `shellcheck`, `shfmt`, `nixfmt` and `pactl`. `nix build` runs shellcheck over both scripts, so it doubles as the lint gate; `nix fmt` formats the Nix files and `shfmt -d` checks the shell ones against the 2-space indent pinned in `.editorconfig`.

## Scripts

- `gamechat_mix.sh`: creates the two remap sinks on the current hardware sink and keeps routing new streams into the catch-all sink.
- `gamechat_balance.sh`: takes `game`, `chat` or `reset` and moves the volume balance between the two sinks by `STEP` percentage points per invocation, clamped to 0–100%.

## Limitations

- Only Discord and WebRTC are recognised as chat applications out of the box; widen `CHAT_MATCH` to add more. The filter matches application, client, binary and node names.
- The chat client's output device still has to be selected manually inside the client.
- Both sinks sit at 50% by default so the balance has headroom in both directions, which costs a little absolute volume.

## License

[MIT](LICENSE) © 2026 Shochraos
