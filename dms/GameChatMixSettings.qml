import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "gamechatMix"

    StyledText {
        width: parent.width
        text: "Game / Chat Mix"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows the balance between the game sink and the chat sink created by gamechat_mix, and moves it when you drag the slider. Game is on the left, chat on the right."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "manageDaemon"
        label: "Manage the gamechat_mix daemon"
        description: "Start and supervise the routing daemon from the shell. Turn this off when a systemd user unit already runs it."
        defaultValue: true
    }

    StringSetting {
        settingKey: "mixCommand"
        label: "Daemon Command"
        description: "Command used when the daemon is managed by the shell. Resolved from PATH."
        placeholder: "gamechat_mix"
        defaultValue: "gamechat_mix"
    }

    StringSetting {
        settingKey: "gameSink"
        label: "Game Sink"
        description: "Must match CATCHALL_SINK in the daemon's environment."
        placeholder: "catchall_sink"
        defaultValue: "catchall_sink"
    }

    StringSetting {
        settingKey: "chatSink"
        label: "Chat Sink"
        description: "Must match DISCORD_SINK in the daemon's environment."
        placeholder: "discord_sink"
        defaultValue: "discord_sink"
    }

    SliderSetting {
        settingKey: "step"
        label: "Keybind Step"
        description: "Percentage points moved by 'dms ipc call gamechat game' and 'dms ipc call gamechat chat'. Match STEP in the daemon's environment so both surfaces agree."
        defaultValue: 2
        minimum: 1
        maximum: 25
        unit: "%"
        leftIcon: "tune"
    }

    StyledText {
        width: parent.width
        text: "Keybind integration: 'dms ipc call gamechat game', '... chat', '... reset', '... setMix <chat percent>' and '... status'. These are equivalent to the gamechat_balance verbs, so either surface can drive the mix."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
