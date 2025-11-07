# Game-Chat-Mix

This repository consists of four bash-scripts which fully implement the "Game-Chat-Mix" functionality of many gaming headsets.
It increments and decrements the volume of Discord audio and all other audio by a fixed amount (default 2%) when executed.

Current limitations: 
- Output volume of both sinks is set to 50% to allow headroom for the increments and decrements.
- Currently only works with Discord as chat application
- Discord output must be set manually in the Discord client
- Output sink is hardcoded in the script and needs to be adjusted manually

## Usage:
0. Ensure you have Pipewire and Pipewire-Pulse installed and running on your system.

1. Clone the repository:
   ```bash
   git clone https://github.com/Shochraos/game-chat-mix.git

2. Add execute permissions to the scripts:
   ```bash
   chmod +x gamechat_mix.sh gamechat_game.sh gamechat_chat.sh gamechat_reset.sh
   
3. Configure the script variables in 'gamechat_mix.sh':
   - Set the `HW_SINK=` variable to your hardware sink
   - You can find the name of your sink by running `pactl list sinks short`
   
4. Add the `gamechat_mix.sh` script to your Desktop Environments autostart applications to run it on login.

5. Bind the `gamechat_chat.sh` and `gamechat_game.sh` scripts to your desired hotkeys to adjust the volume mix.

## Scripts:
- `gamechat_mix.sh`: The main script that creates the sinks, continuously monitors the audio streams and moves them in the correct sink
- `gamechat_game.sh`: Increases the game audio volume and decreases the Discord audio volume
- `gamechat_chat.sh`: Increases the Discord audio volume and decreases the game audio volume
- `gamechat_reset.sh`: Resets both audio streams to 50% volume

## Future Improvements:
- Add support for more chat applications
- Automatically detect the default output sink