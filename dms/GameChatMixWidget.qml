import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Templates as T
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "internal" as Mix

PluginComponent {
    id: root

    layerNamespacePlugin: "gamechat-mix"
    popoutWidth: Math.max(160, Math.min(360, (parentScreen?.width || 384) - 24))

    readonly property var mix: Mix.GameChatState
    readonly property int gamePercent: mix.gamePercent
    readonly property int chatPercent: mix.chatPercent
    readonly property string gameValue: gamePercent >= 0 ? `${gamePercent}%` : "—"
    readonly property string chatValue: chatPercent >= 0 ? `${chatPercent}%` : "—"
    readonly property string spokenValues: `Game ${gamePercent >= 0 ? gameValue : "unavailable"}, Chat ${chatPercent >= 0 ? chatValue : "unavailable"}`

    component MixGlyph: DankIcon {
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

    component MixButton: T.Button {
        id: button
        property string glyph: ""
        property bool showLabel: false
        implicitWidth: Math.max(44, implicitContentWidth + 2 * Theme.spacingS)
        implicitHeight: Math.max(44, implicitContentHeight + Theme.spacingXS)
        padding: Theme.spacingS
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: true
        hoverEnabled: true
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: {
            if (enabled)
                clicked();
        }
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()

        background: Rectangle {
            radius: Theme.cornerRadius
            color: button.down ? Theme.surfacePressed : button.hovered || button.showLabel ? Theme.surfaceHover : "transparent"
            border.width: button.visualFocus ? 2 : 0
            border.color: Theme.surfaceText
        }

        contentItem: Item {
            implicitWidth: button.showLabel ? caption.implicitWidth : glyphItem.width
            implicitHeight: button.showLabel ? caption.implicitHeight : glyphItem.height

            MixGlyph {
                id: glyphItem
                anchors.centerIn: parent
                name: button.glyph
                size: Theme.iconSize
                visible: !button.showLabel
                color: button.enabled ? Theme.surfaceText : Theme.outline
            }

            StyledText {
                id: caption
                anchors.centerIn: parent
                text: button.text
                font.pixelSize: Theme.fontSizeMedium
                visible: button.showLabel
                Accessible.ignored: true
            }
        }

        Controls.ToolTip.visible: hovered && !showLabel
        Controls.ToolTip.delay: 600
        Controls.ToolTip.text: text
        HoverHandler {
            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
                    slider.forceActiveFocus(Qt.TabFocusReason);
                else if (settingsButton.visible)
                    settingsButton.forceActiveFocus(Qt.TabFocusReason);
                else
                    closeButton.forceActiveFocus(Qt.TabFocusReason);
            }

            onParentPopoutChanged: Qt.callLater(focusMix)
            Connections {
                target: popup.parentPopout
                function onOpened() { Qt.callLater(popup.focusMix); }
            }

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXS

                    StyledText {
                        Layout.fillWidth: true
                        text: "Game / Chat Mix"
                        font.pixelSize: Theme.fontSizeLarge + (popup.width >= 260 ? 4 : 0)
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    MixButton {
                        objectName: "mixReset"
                        text: "Reset to 50 / 50"
                        glyph: "restart_alt"
                        enabled: root.mix.ready
                        visible: enabled
                        onClicked: root.mix.setMix(50)
                    }

                    MixButton {
                        id: closeButton
                        objectName: "mixClose"
                        text: "Close mix"
                        glyph: "close"
                        onClicked: popup.closePopout?.()
                    }
                }

                RowLayout {
                    id: valuesRow
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    readonly property bool showGlyphs: width >= Math.max(220, Theme.fontSizeMedium * 16)

                    MixGlyph {
                        name: "sports_esports"
                        size: Theme.iconSize
                        visible: valuesRow.showGlyphs
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        objectName: "gameMixLabel"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: `Game ${root.gameValue}`
                        font.pixelSize: Theme.fontSizeMedium
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }

                    StyledText {
                        objectName: "chatMixLabel"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: `Chat ${root.chatValue}`
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                    }

                    MixGlyph {
                        name: "headset_mic"
                        size: Theme.iconSize
                        visible: valuesRow.showGlyphs
                        color: Theme.surfaceVariantText
                    }
                }

                T.Slider {
                    id: slider
                    objectName: "mixSlider"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    enabled: root.mix.ready
                    from: 0
                    to: 100
                    stepSize: 1
                    snapMode: T.Slider.SnapAlways
                    focusPolicy: Qt.StrongFocus
                    activeFocusOnTab: true
                    hoverEnabled: true
                    leftPadding: 4
                    rightPadding: 4

                    property bool syncing: false
                    readonly property real minimumValue: from
                    readonly property real maximumValue: to

                    Accessible.role: Accessible.Slider
                    Accessible.name: "Game / Chat balance"
                    Accessible.description: `${root.spokenValues}. Left favors Game, right favors Chat.`

                    function syncFromMix() {
                        if (pressed)
                            return;
                        syncing = true;
                        value = Math.max(from, Math.min(to, root.chatPercent));
                        syncing = false;
                    }

                    Component.onCompleted: syncFromMix()
                    onValueChanged: {
                        if (enabled && !syncing)
                            root.mix.setMix(value);
                    }
                    onPressedChanged: {
                        if (!pressed)
                            Qt.callLater(syncFromMix);
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                            value = event.key === Qt.Key_Home ? from : to;
                            event.accepted = true;
                        }
                    }

                    Connections {
                        target: root
                        function onChatPercentChanged() { slider.syncFromMix(); }
                    }

                    HoverHandler {
                        cursorShape: slider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: "transparent"
                        border.width: slider.activeFocus ? 2 : 0
                        border.color: Theme.surfaceText
                    }

                    background: Rectangle {
                        id: track
                        objectName: "mixTrack"
                        x: slider.leftPadding + slider.handle.width / 2
                        y: (slider.height - height) / 2
                        width: Math.max(0, slider.availableWidth - slider.handle.width)
                        height: 8
                        radius: height / 2
                        color: Qt.tint(Theme.surfaceContainer, Theme.withAlpha(Theme.surfaceText, 0.61))
                        opacity: slider.enabled ? 1 : 0.5

                        Rectangle {
                            width: parent.width * slider.visualPosition
                            height: parent.height
                            radius: Math.min(parent.radius, width / 2)
                            color: Theme.primary
                            visible: slider.enabled
                        }
                    }

                    handle: Rectangle {
                        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                        y: (slider.height - height) / 2
                        width: slider.pressed ? 18 : 16
                        height: width
                        radius: width / 2
                        color: Theme.primary
                        border.color: Theme.surfaceContainer
                        border.width: 2
                        visible: slider.enabled
                    }
                }

                StyledText {
                    objectName: "mixStatus"
                    Layout.fillWidth: true
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
                    Layout.fillWidth: true
                    visible: popup.diagnostic.length > 0
                    text: popup.diagnostic
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    maximumLineCount: 4
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: popup.showRecovery
                    text: !popup.managed ? "Check your routing service and its sink names."
                        : root.mix.nameError || popup.launchIssue ? "Check Game / Chat Mix in Plugins."
                        : "Check the output in Settings → System → Audio, then check the sink names in Plugins.";
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                }

                MixButton {
                    id: settingsButton
                    objectName: "mixSettings"
                    visible: popup.showRecovery
                    text: "Open Plugins"
                    showLabel: true
                    onClicked: {
                        popup.closePopout?.();
                        PopoutService.openSettingsWithTab("plugins");
                    }
                }
            }
        }
    }
}