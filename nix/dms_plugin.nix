{
  lib,
  stdenvNoCC,
  gamechat_mix,
}:

stdenvNoCC.mkDerivation {
  pname = "gamechat-mix-dms-plugin";
  version = (builtins.fromJSON (builtins.readFile ../dms/plugin.json)).version;

  src = ../dms;

  gamechat_mix = "${gamechat_mix}/bin/gamechat_mix";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r ./* $out/
    substituteAllInPlace $out/GameChatMixDaemon.qml
    runHook postInstall
  '';

  passthru.pluginId = "gamechatMix";

  meta = {
    description = "DankMaterialShell plugin for the game/chat audio mix, with the routing daemon bundled";
    homepage = "https://github.com/Shochraos/game-chat-mix";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
