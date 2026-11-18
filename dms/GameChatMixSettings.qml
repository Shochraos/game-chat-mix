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
        text: "Game is on the left, Chat on the right. Drag the slider or use the arrow keys. Reset sets both to 50%."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }

    ToggleSetting {
        settingKey: "manageDaemon"
        label: "Manage the gamechat_mix daemon"
        description: "Start the routing daemon from the shell. Turn this off if a systemd user service or another launcher runs it."
        defaultValue: true
    }

    StringSetting {
        settingKey: "mixCommand"
        label: "Daemon command"
        description: "Leave blank for the packaged wrapper or the script next to the plugin. For an override, quote paths and arguments containing spaces. No shell expansion."
        placeholder: "auto"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "gameSink"
        label: "Game sink name"
        description: "Lookup only. Leave blank for CATCHALL_SINK from the shell environment in managed mode, or catchall_sink otherwise. Enter the service's exact name for a custom external sink."
        placeholder: "Automatic"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "chatSink"
        label: "Chat sink name"
        description: "Lookup only. Leave blank for DISCORD_SINK from the shell environment in managed mode, or discord_sink otherwise. Enter the service's exact name for a custom external sink."
        placeholder: "Automatic"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "step"
        label: "Keybind step"
        description: "Percentage points moved by the game and chat IPC calls. Match STEP in the environment where you run gamechat_balance."
        defaultValue: 2
        minimum: 1
        maximum: 25
        unit: "%"
        leftIcon: "tune"
    }

    StyledText {
        width: parent.width
        text: "IPC: dms ipc call gamechat game, chat, reset, setMix <chat percent>, or status."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.Wrap
    }
}
