{
  lib,
  writeShellApplication,
  gawk,
  pulseaudio,
}:
writeShellApplication {
  name = "gamechat_balance";

  runtimeInputs = [
    gawk
    pulseaudio
  ];

  text = builtins.readFile ../gamechat_balance.sh;

  meta = {
    description = "Shifts the volume balance between the chat and game sinks";
    homepage = "https://github.com/Shochraos/game-chat-mix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
