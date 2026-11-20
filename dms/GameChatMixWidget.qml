import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "internal" as Mix

PluginComponent {
    id: root

    layerNamespacePlugin: "gamechat-mix"
    popoutWidth: Math.max(280, Math.min(360, (parentScreen?.width || 384) - 24))

    readonly property var mix: Mix.GameChatState
    readonly property int gamePercent: mix.gamePercent
    readonly property int chatPercent: mix.chatPercent
    readonly property string gameValue: gamePercent >= 0 ? `${gamePercent}%` : "—"
    readonly property string chatValue: chatPercent >= 0 ? `${chatPercent}%` : "—"
    readonly property string spokenValues: `Game ${gamePercent >= 0 ? gameValue : "unavailable"}, Chat ${chatPercent >= 0 ? chatValue : "unavailable"}`

    component MixGlyph: DIcon {
        implicitWidth: Math.ceil(size) + 6
        implicitHeight: Math.ceil(size * 1.2) + 4
        smoothTransform: true
        Accessible.ignored: true
    }

    component PillContent: Item {
        id: pill
        required property bool vertical
        implicitWidth: contents.implicitWidth + 4
        implicitHeight: contents.implicitHeight + 4
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Game / Chat Mix"
        Accessible.description: root.spokenValues
        Accessible.onPressAction: root.triggerPopout()
        Keys.onSpacePressed: root.triggerPopout()
        Keys.onReturnPressed: root.triggerPopout()
        Keys.onEnterPressed: root.triggerPopout()

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Theme.cornerRadius
            border.color: Theme.surfaceText
            border.width: pill.activeFocus ? 2 : 0
        }

        GridLayout {
            id: contents
            anchors.centerIn: parent
            columns: pill.vertical ? 1 : 3
            columnSpacing: Theme.spacingXS
            rowSpacing: 2

            MixGlyph {
                name: "sports_esports"
                size: root.iconSize
                visible: pill.vertical ? implicitWidth + 4 <= root.widgetThickness : implicitHeight + 4 <= root.barThickness
                Layout.alignment: Qt.AlignCenter
            }

            NumericText {
                text: pill.vertical ? root.gameValue.replace("%", "") : `${root.gameValue.replace("%", "")} / ${root.chatValue.replace("%", "")}`
                reserveText: pill.vertical ? "100" : "100 / 100"
                Layout.preferredWidth: reservedWidth
                Layout.alignment: Qt.AlignCenter
                font.pixelSize: Theme.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
                Accessible.ignored: true
            }

            NumericText {
                visible: pill.vertical
                text: root.chatValue.replace("%", "")
                reserveText: "100"
                Layout.preferredWidth: reservedWidth
                Layout.alignment: Qt.AlignCenter
                font.pixelSize: Theme.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
                Accessible.ignored: true
            }

            MixGlyph {
                name: "headset_mic"
                size: root.iconSize
                visible: pill.vertical ? implicitWidth + 4 <= root.widgetThickness : implicitHeight + 4 <= root.barThickness
                Layout.alignment: Qt.AlignCenter
            }
        }
    }

    horizontalBarPill: Component {
        PillContent { vertical: false }
    }

    verticalBarPill: Component {
        PillContent { vertical: true }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popup
            objectName: "mixPopup"

            headerText: "Game / Chat Mix"
            headerActions: Component {
                DActionButton {
                    objectName: "mixReset"
                    iconName: "restart_alt"
                    tooltipText: "Reset to 50 / 50"
                    enabled: root.mix.ready
                    visible: enabled
                    onClicked: root.mix.setMix(50)
                }
            }

            readonly property var supervisor: root.mix.supervisor
            readonly property bool managed: root.mix.manageDaemon
            readonly property string launchIssue: managed && supervisor ? (supervisor.commandError || supervisor.failure) : ""
            readonly property bool waiting: root.mix.loading && !launchIssue
            readonly property bool hasIssue: !!root.mix.nameError || !!launchIssue || (!root.mix.ready && !waiting)
            readonly property string diagnostic: managed && (hasIssue || waiting) ? (supervisor?.lastDiagnostic ?? "") : ""
            readonly property bool showRecovery: hasIssue || !!diagnostic

            function focusMix() {
                if (!visible || (parentPopout && !parentPopout.shouldBeVisible))
                    return;
                if (slider.enabled)
                    slider.forceActiveFocus(Qt.OtherFocusReason);
                else if (settingsButton.visible)
                    settingsButton.forceActiveFocus(Qt.OtherFocusReason);
            }

            onParentPopoutChanged: Qt.callLater(focusMix)
            Connections {
                target: popup.parentPopout
                function onOpened() { Qt.callLater(popup.focusMix); }
            }

            Item {
                width: parent.width
                implicitHeight: body.implicitHeight + Theme.spacingS

                Column {
                    id: body
                    x: Theme.spacingS
                    y: Theme.spacingS
                    width: parent.width - Theme.spacingS * 2
                    spacing: Theme.spacingS

                    RowLayout {
                        id: valuesRow
                        width: parent.width
                        spacing: Theme.spacingM
                        readonly property bool showGlyphs: width >= Math.max(200, Theme.fontSizeMedium * 15)

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: Theme.spacingXS

                            MixGlyph {
                                name: "sports_esports"
                                size: Theme.iconSize - 4
                                visible: valuesRow.showGlyphs
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }

                            StyledText {
                                objectName: "gameMixLabel"
                                Layout.fillWidth: true
                                text: `Game ${root.gameValue}`
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: Theme.spacingXS

                            StyledText {
                                objectName: "chatMixLabel"
                                Layout.fillWidth: true
                                text: `Chat ${root.chatValue}`
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                Layout.alignment: Qt.AlignVCenter
                            }

                            MixGlyph {
                                name: "headset_mic"
                                size: Theme.iconSize - 4
                                visible: valuesRow.showGlyphs
                                color: Theme.surfaceVariantText
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    DSlider {
                        id: slider
                        objectName: "mixSlider"
                        width: parent.width
                        enabled: root.mix.ready
                        minimum: 0
                        maximum: 100
                        step: 1
                        unit: "%"
                        showValue: false
                        Accessible.name: "Game / Chat balance"
                        Accessible.description: `${root.spokenValues}. Left favors Game, right favors Chat.`

                        Binding on value {
                            value: root.mix.ready ? root.mix.clampPercent(root.chatPercent) : 50
                            when: !slider.isDragging
                            restoreMode: Binding.RestoreNone
                        }

                        onSliderValueChanged: newValue => {
                            if (root.mix.ready)
                                root.mix.setMix(newValue);
                        }
                    }

                    StyledText {
                        objectName: "mixStatus"
                        width: parent.width
                        visible: text.length > 0
                        text: {
                            if (root.mix.nameError)
                                return root.mix.nameError;
                            if (popup.waiting)
                                return "Waiting for the audio sinks…";
                            const lines = [];
                            if (popup.launchIssue)
                                lines.push(popup.launchIssue + (popup.supervisor.phase === "retry" ? " Retrying in 5 s." : ""));
                            if (root.gamePercent < 0)
                                lines.push(root.mix.unavailableReason("Game", root.mix.gameName, root.mix.gameNode));
                            if (root.chatPercent < 0)
                                lines.push(root.mix.unavailableReason("Chat", root.mix.chatName, root.mix.chatNode));
                            return lines.join("\n");
                        }
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }

                    StyledText {
                        width: parent.width
                        visible: popup.diagnostic.length > 0
                        text: popup.diagnostic
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        maximumLineCount: 4
                    }

                    StyledText {
                        width: parent.width
                        visible: popup.showRecovery
                        text: !popup.managed ? "Check your routing service and its sink names."
                            : root.mix.nameError || popup.launchIssue ? "Check Game / Chat Mix in Plugins."
                            : "Check the output in Settings → System → Audio, then check the sink names in Plugins.";
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }

                    DButton {
                        id: settingsButton
                        objectName: "mixSettings"
                        visible: popup.showRecovery
                        text: "Open Plugins"
                        onClicked: {
                            popup.closePopout?.();
                            PopoutService.openSettingsWithTab("plugins");
                        }
                    }
                }
            }
        }
    }
}