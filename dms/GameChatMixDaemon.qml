import QtQuick
import Quickshell.Io
import qs.Modules.Plugins
import "internal" as Mix

PluginComponent {
    id: root

    readonly property var mix: Mix.GameChatState
    readonly property int step: pluginData.step || 2
    readonly property string bakedMixCommand: "@gamechat_mix@"
    readonly property string siblingMixScript: decodeURIComponent(Qt.resolvedUrl("gamechat_mix.sh").toString().replace(/^file:\/\//, ""))
    readonly property var desiredCommand: parseCommand(pluginData.mixCommand || "")
    readonly property string commandError: desiredCommand.length ? "" : "Check the daemon command: quote paths with spaces and close any quotes."
    readonly property bool configured: mix.supervisor === root && !!pluginService && !!pluginId
    readonly property bool shouldManage: configured && mix.manageDaemon && !mix.nameError && !commandError
    readonly property string desiredKey: shouldManage ? JSON.stringify(desiredCommand) : ""
    property string activeKey: ""
    property string phase: "idle"
    property string failure: ""
    property string lastDiagnostic: ""
    property string stderrTail: ""
    property bool tailTruncated: false
    readonly property int diagnosticLimit: 320
    property var recentWarnings: []
    property double lastWarningAt: 0

    Component.onCompleted: {
        if (!mix.supervisor)
            mix.supervisor = root;
    }
    Component.onDestruction: {
        if (mix?.supervisor === root)
            mix.supervisor = null;
    }

    function parseCommand(command) {
        if (!command.trim())
            return bakedMixCommand.startsWith("/") ? [bakedMixCommand] : [siblingMixScript];
        const words = [];
        let word = "";
        let quote = "";
        let inWord = false;
        for (let i = 0; i < command.length; i++) {
            const ch = command[i];
            if (ch === "\\" && quote !== "'") {
                if (++i === command.length)
                    return [];
                word += command[i];
                inWord = true;
            } else if (quote) {
                if (ch === quote)
                    quote = "";
                else
                    word += ch;
            } else if (ch === "'" || ch === '"') {
                quote = ch;
                inWord = true;
            } else if (/\s/.test(ch)) {
                if (inWord) {
                    words.push(word);
                    word = "";
                    inWord = false;
                }
            } else {
                word += ch;
                inWord = true;
            }
        }
        if (quote)
            return [];
        if (inWord)
            words.push(word);
        return words[0] ? words : [];
    }

    function consumeStderr(chunk) {
        let start = 0;
        while (start < chunk.length) {
            const newline = chunk.indexOf("\n", start);
            const end = newline < 0 ? chunk.length : newline;
            const length = end - start;
            tailTruncated = tailTruncated || stderrTail.length + length > diagnosticLimit;
            stderrTail = (stderrTail + chunk.slice(Math.max(start, end - diagnosticLimit), end)).slice(-diagnosticLimit);
            if (newline < 0)
                return;
            finishDiagnostic();
            start = end + 1;
        }
    }

    function finishDiagnostic() {
        const line = stderrTail.replace(/[\x00-\x1f\x7f]/g, " ").trim();
        const message = tailTruncated ? `…${line}` : line;
        stderrTail = "";
        tailTruncated = false;
        if (!line || /^gamechat: (?:retrying|event stream ended, reconnecting) in \d+s$/.test(line))
            return;
        lastDiagnostic = message;
        const now = Date.now();
        if (!recentWarnings.includes(message) && now - lastWarningAt >= 5000) {
            recentWarnings = [...recentWarnings.slice(-7), message];
            lastWarningAt = now;
            console.warn("GameChatMix:", message);
        }
    }

    function mixReport() {
        return JSON.stringify({
            game: mix.gamePercent,
            chat: mix.chatPercent,
            managedDaemon: mix.manageDaemon
        });
    }

    function shiftBalance(chatDelta, gameDelta) {
        if (!mix.ready)
            return "SINKS_UNAVAILABLE";
        const chat = mix.chatPercent;
        const game = mix.gamePercent;
        mix.chatNode.audio.volume = mix.clampPercent(chat + chatDelta) / 100;
        mix.gameNode.audio.volume = mix.clampPercent(game + gameDelta) / 100;
        return mixReport();
    }

    onDesiredKeyChanged: {
        retryTimer.stop();
        reconcileTimer.restart();
    }

    function reconcile() {
        if (phase === "stopping")
            return;
        if (mixProcess.running) {
            if (activeKey !== desiredKey) {
                phase = "stopping";
                mixProcess.running = false;
            }
            return;
        }
        failure = "";
        lastDiagnostic = "";
        if (shouldManage)
            startDaemon();
        else
            phase = "idle";
    }

    function startDaemon() {
        if (!shouldManage || mixProcess.running)
            return;
        activeKey = desiredKey;
        stderrTail = "";
        tailTruncated = false;
        phase = "starting";
        mixProcess.command = desiredCommand;
        mixProcess.running = true;
    }

    function finishRun(reason, retry) {
        finishDiagnostic();
        if (phase === "stopping" || activeKey !== desiredKey) {
            phase = "idle";
            reconcileTimer.restart();
            return;
        }
        failure = reason;
        phase = retry ? "retry" : "stopped";
        if (retry)
            retryTimer.restart();
    }

    Process {
        id: mixProcess
        environment: ({
            GAMECHAT_WAIT_FOR_LOCK: "1",
            CATCHALL_SINK: root.mix.managedGameName,
            DISCORD_SINK: root.mix.managedChatName
        })
        stderr: SplitParser {
            splitMarker: ""
            onRead: chunk => root.consumeStderr(chunk)
        }
        onStarted: {
            if (root.phase === "starting") {
                root.failure = "";
                root.phase = "running";
            }
        }
        onRunningChanged: {
            if (!running && root.phase === "starting")
                root.finishRun("Could not start the routing daemon.", true);
            else if (!running && root.phase === "stopping")
                root.finishRun("", false);
        }
        onExited: (exitCode, exitStatus) => {
            const failed = exitCode !== 0 || exitStatus !== 0;
            const reason = exitStatus !== 0 ? "The routing daemon crashed."
                : failed ? `The routing daemon exited (code ${exitCode}).` : "The routing daemon stopped.";
            root.finishRun(reason, failed);
        }
    }

    Timer {
        id: reconcileTimer
        interval: 100
        onTriggered: root.reconcile()
    }

    Timer {
        id: retryTimer
        interval: 5000
        onTriggered: root.startDaemon()
    }

    Loader {
        active: root.mix.supervisor === root
        sourceComponent: IpcHandler {
            target: "gamechat"

            function game(): string {
                return root.shiftBalance(-root.step, root.step);
            }

            function chat(): string {
                return root.shiftBalance(root.step, -root.step);
            }

            function reset(): string {
                if (!root.mix.ready)
                    return "SINKS_UNAVAILABLE";
                root.mix.setMix(50);
                return root.mixReport();
            }

            function setMix(chatPercent: string): string {
                const parsed = parseInt(chatPercent, 10);
                if (isNaN(parsed))
                    return "INVALID_PERCENT";
                if (!root.mix.ready)
                    return "SINKS_UNAVAILABLE";
                root.mix.setMix(parsed);
                return root.mixReport();
            }

            function status(): string {
                return root.mixReport();
            }
        }
    }
}
