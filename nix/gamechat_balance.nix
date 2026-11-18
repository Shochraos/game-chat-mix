{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  pulseaudio,
  util-linux,
}:
writeShellApplication {
  name = "gamechat_balance";

  runtimeInputs = [
    coreutils
    gawk
    pulseaudio
    util-linux
  ];

  text = builtins.readFile ../dms/gamechat_balance.sh;

  meta = {
    description = "Shifts the volume balance between the chat and game sinks";
    homepage = "https://github.com/Shochraos/game-chat-mix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
