import QtQuick
import Quickshell.Services.Pipewire
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "gamechat-mix"

    readonly property string chatSinkName: pluginData.chatSink || "discord_sink"
    readonly property string gameSinkName: pluginData.gameSink || "catchall_sink"

    readonly property var chatNode: Pipewire.nodes.values.find(node => node.name === root.chatSinkName) ?? null
    readonly property var gameNode: Pipewire.nodes.values.find(node => node.name === root.gameSinkName) ?? null
    readonly property var trackedNodes: [root.chatNode, root.gameNode].filter(node => node !== null)

    readonly property int chatPercent: root.chatNode?.audio ? Math.round(root.chatNode.audio.volume * 100) : -1
    readonly property int gamePercent: root.gameNode?.audio ? Math.round(root.gameNode.audio.volume * 100) : -1
    readonly property bool ready: root.chatPercent >= 0 && root.gamePercent >= 0

    function applyMix(chatTarget) {
        if (!root.ready)
            return;
        const target = Math.max(0, Math.min(100, Math.round(chatTarget)));
        root.chatNode.audio.volume = target / 100;
        root.gameNode.audio.volume = (100 - target) / 100;
    }

    PwObjectTracker {
        objects: root.trackedNodes
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: "sports_esports"
                size: root.iconSize
                color: root.ready ? Theme.surfaceText : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }

            NumericText {
                width: reservedWidth
                text: root.ready ? `${root.gamePercent} / ${root.chatPercent}` : "-- / --"
                reserveText: "100 / 100"
                isMonospace: false
                font.pixelSize: Theme.fontSizeMedium
                color: root.ready ? Theme.surfaceText : Theme.outline
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            DankIcon {
                name: "headset_mic"
                size: root.iconSize
                color: root.ready ? Theme.surfaceText : Theme.outline
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                name: "sports_esports"
                size: root.iconSize
                color: root.ready ? Theme.surfaceText : Theme.outline
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                width: reservedWidth
                text: root.ready ? `${root.gamePercent}` : "--"
                reserveText: "100"
                isMonospace: false
                font.pixelSize: Theme.fontSizeMedium
                color: root.ready ? Theme.surfaceText : Theme.outline
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            NumericText {
                width: reservedWidth
                text: root.ready ? `${root.chatPercent}` : "--"
                reserveText: "100"
                isMonospace: false
                font.pixelSize: Theme.fontSizeMedium
                color: root.ready ? Theme.surfaceText : Theme.outline
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            DankIcon {
                name: "headset_mic"
                size: root.iconSize
                color: root.ready ? Theme.surfaceText : Theme.outline
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: mixPopout

            headerText: "Game / Chat Mix"
            showCloseButton: true

            headerActions: Component {
                DankActionButton {
                    iconName: "restart_alt"
                    enabled: root.ready
                    tooltipText: "Reset to 50 / 50"
                    onClicked: root.applyMix(50)
                }
            }

            Item {
                width: parent.width
                height: labelRow.implicitHeight

                Row {
                    id: labelRow
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "sports_esports"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.ready ? `Game ${root.gamePercent}%` : "Game --"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    spacing: Theme.spacingXS

                    StyledText {
                        text: root.ready ? `Chat ${root.chatPercent}%` : "Chat --"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "headset_mic"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            DankSlider {
                id: mixSlider

                width: parent.width
                enabled: root.ready
                minimum: 0
                maximum: 100
                step: 1
                unit: "%"
                showValue: true
                leftIcon: "sports_esports"
                rightIcon: "headset_mic"
                value: root.ready ? root.chatPercent : 50

                onSliderValueChanged: newValue => root.applyMix(newValue)
                onSliderDragFinished: {
                    if (root.ready)
                        mixSlider.value = root.chatPercent;
                }

                Connections {
                    target: root
                    function onChatPercentChanged() {
                        if (!mixSlider.isDragging && root.ready)
                            mixSlider.value = root.chatPercent;
                    }
                }
            }
        }
    }

    popoutWidth: 360
}
