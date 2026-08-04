{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  gnused,
  pulseaudio,
}:
writeShellApplication {
  name = "gamechat_mix";

  runtimeInputs = [
    coreutils
    gawk
    gnused
    pulseaudio
  ];

  bashOptions = [ "nounset" ];

  text = builtins.readFile ../gamechat_mix.sh;

  meta = {
    description = "Routing daemon that keeps chat and game audio on separate remap sinks";
    homepage = "https://github.com/Shochraos/game-chat-mix";
    platforms = lib.platforms.linux;
  };
}
