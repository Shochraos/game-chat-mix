import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string chatSinkName: pluginData.chatSink || "discord_sink"
    readonly property string gameSinkName: pluginData.gameSink || "catchall_sink"
    readonly property int step: pluginData.step || 2
    readonly property int resetVolume: 50
    readonly property bool manageDaemon: pluginData.manageDaemon !== undefined ? pluginData.manageDaemon : true
    readonly property string mixCommand: pluginData.mixCommand || "gamechat_mix"

    readonly property var chatNode: Pipewire.nodes.values.find(node => node.name === root.chatSinkName) ?? null
    readonly property var gameNode: Pipewire.nodes.values.find(node => node.name === root.gameSinkName) ?? null
    readonly property var trackedNodes: [root.chatNode, root.gameNode].filter(node => node !== null)

    function percentOf(node) {
        return node?.audio ? Math.round(node.audio.volume * 100) : -1;
    }

    function clampPercent(value) {
        return Math.max(0, Math.min(100, Math.round(value)));
    }

    function writePercent(node, percent) {
        node.audio.volume = percent / 100;
    }

    function mixReport() {
        return JSON.stringify({
            game: root.percentOf(root.gameNode),
            chat: root.percentOf(root.chatNode),
            managedDaemon: root.manageDaemon
        });
    }

    function shiftBalance(chatDelta, gameDelta) {
        const chat = percentOf(chatNode);
        const game = percentOf(gameNode);
        if (chat < 0 || game < 0)
            return "SINKS_UNAVAILABLE";
        writePercent(chatNode, clampPercent(chat + chatDelta));
        writePercent(gameNode, clampPercent(game + gameDelta));
        return mixReport();
    }

    PwObjectTracker {
        objects: root.trackedNodes
    }

    Process {
        id: mixProcess
        command: root.mixCommand.split(/\s+/).filter(part => part.length > 0)
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim())
                    console.warn("GameChatMix daemon:", text.trim());
            }
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            console.warn("GameChatMix daemon exited:", exitCode);
            if (root.manageDaemon)
                mixRestartTimer.start();
        }
    }

    Timer {
        id: mixStartTimer
        interval: 100
        running: root.manageDaemon
        onTriggered: mixProcess.running = true
    }

    Timer {
        id: mixRestartTimer
        interval: 5000
        onTriggered: mixProcess.running = root.manageDaemon
    }

    onManageDaemonChanged: {
        if (!manageDaemon) {
            mixRestartTimer.stop();
            mixProcess.running = false;
        }
    }

    IpcHandler {
        target: "gamechat"

        function game(): string {
            return root.shiftBalance(-root.step, root.step);
        }

        function chat(): string {
            return root.shiftBalance(root.step, -root.step);
        }

        function reset(): string {
            if (root.percentOf(root.chatNode) < 0 || root.percentOf(root.gameNode) < 0)
                return "SINKS_UNAVAILABLE";
            root.writePercent(root.chatNode, root.resetVolume);
            root.writePercent(root.gameNode, root.resetVolume);
            return root.mixReport();
        }

        function setMix(chatPercent: string): string {
            const parsed = parseInt(chatPercent, 10);
            if (isNaN(parsed))
                return "INVALID_PERCENT";
            if (root.percentOf(root.chatNode) < 0 || root.percentOf(root.gameNode) < 0)
                return "SINKS_UNAVAILABLE";
            const target = root.clampPercent(parsed);
            root.writePercent(root.chatNode, target);
            root.writePercent(root.gameNode, 100 - target);
            return root.mixReport();
        }

        function status(): string {
            return root.mixReport();
        }
    }
}
