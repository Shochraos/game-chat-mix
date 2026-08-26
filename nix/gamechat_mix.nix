{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  pulseaudio,
  util-linux,
}:
writeShellApplication {
  name = "gamechat_mix";

  runtimeInputs = [
    coreutils
    gawk
    pulseaudio
    util-linux
  ];

  bashOptions = [ "nounset" ];

  text = builtins.readFile ../scripts/gamechat_mix.sh;

  meta = {
    description = "Routing daemon that keeps chat and game audio on separate remap sinks";
    homepage = "https://github.com/Shochraos/game-chat-mix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
