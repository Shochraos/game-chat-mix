pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property Item supervisor: null
    readonly property var settings: supervisor?.pluginData ?? ({})
    readonly property bool manageDaemon: settings.manageDaemon ?? true
    readonly property string managedGameName: Quickshell.env("CATCHALL_SINK") || "catchall_sink"
    readonly property string managedChatName: Quickshell.env("DISCORD_SINK") || "discord_sink"
    readonly property string gameName: settings.gameSink || (manageDaemon ? managedGameName : "catchall_sink")
    readonly property string chatName: settings.chatSink || (manageDaemon ? managedChatName : "discord_sink")
    readonly property string nameError: {
        const valid = /^[A-Za-z0-9_.-]+$/;
        if (!valid.test(gameName) || !valid.test(chatName))
            return "Sink names can only use letters, digits, dots, underscores and hyphens.";
        if (gameName === chatName)
            return "Game and Chat must use different sink names.";
        if (manageDaemon && (gameName !== managedGameName || chatName !== managedChatName))
            return `The shell daemon uses Game “${managedGameName}” and Chat “${managedChatName}”. Match those names or leave both fields blank.`;
        return "";
    }

    readonly property var gameNode: findSink(gameName)
    readonly property var chatNode: findSink(chatName)
    readonly property var trackedNodes: [gameNode, chatNode].filter((node, index, nodes) => node && nodes.indexOf(node) === index)
    readonly property int gamePercent: percentOf(gameNode)
    readonly property int chatPercent: percentOf(chatNode)
    readonly property bool ready: !nameError && gamePercent >= 0 && chatPercent >= 0
    readonly property bool loading: !ready && !nameError && !graceElapsed
    property bool graceElapsed: false

    function findSink(name) {
        return Pipewire.nodes.values.find(node => node.name === name && node.isSink && !node.isStream) ?? null;
    }

    function percentOf(node) {
        if (!node?.ready || !node.audio?.volumes.length || !Number.isFinite(node.audio.volume))
            return -1;
        return Math.round(node.audio.volume * 100);
    }

    function unavailableReason(label, name, node) {
        return node ? `${label} sink “${name}”: volume not available.` : `${label} sink “${name}” not found.`;
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Math.round(value)));
    }

    function setMix(chatTarget) {
        if (!ready)
            return;
        const target = clampPercent(chatTarget);
        chatNode.audio.volume = target / 100;
        gameNode.audio.volume = (100 - target) / 100;
    }

    function restartGrace() {
        graceElapsed = false;
        if (!ready)
            graceTimer.restart();
    }

    onGameNameChanged: restartGrace()
    onChatNameChanged: restartGrace()
    onReadyChanged: restartGrace()

    Timer {
        id: graceTimer
        interval: 1500
        running: !root.ready && !root.graceElapsed
        onTriggered: root.graceElapsed = true
    }

    PwObjectTracker {
        objects: root.trackedNodes
    }
}
