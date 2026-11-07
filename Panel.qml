import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "rconnect.panel"
  ipcTarget: "rconnect.panel"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var primary: phone.primary
  readonly property bool hasRequest: phone.requests.length > 0
  readonly property bool showBattery: setting("showBattery", true) === true
  readonly property string barLabel: showBattery && primary && phone.primaryBattery && phone.primaryBattery.charge >= 0 && !(bar && bar.vertical)
    ? Commons.I18n.formatNumber(phone.primaryBattery.charge) + "%" : ""

  readonly property string heroMeta: {
    if (!phone.streamUp) return phone.serviceActive ? "Connecting to rust-connect…" : "rust-connect is not running"
    if (hasRequest) return phone.requests[0].name + " wants to pair"
    if (primary) return Model.stateText(primary, phone.primaryBattery)
    if (phone.devices.length === 0) return "No devices found yet"
    return "No phone connected"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    phone.checkService()
    if (phone.streamUp) phone.refreshDevices()
    if (primary) phone.requestBattery(primary.id)
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Service {
    id: phone
    settings: root.settings
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function ring(): string { if (!root.primary) return "no device"; phone.ring(root.primary.id); return "ok" }
    function sendClipboard(): string { if (!root.primary) return "no device"; phone.sendClipboard(root.primary.id); return "ok" }
    function sendFiles(): string { if (!root.primary) return "no device"; phone.sendFiles(root.primary.id); return "ok" }
    function status(): string {
      if (!phone.streamUp) return "offline"
      return root.primary ? root.primary.name + ": " + Model.stateText(root.primary, phone.primaryBattery) : "no device"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.primary ? Model.deviceGlyph(root.primary.type) : Model.GLYPH.phone
    labelText: root.barLabel
    slotSize: Style.bar.iconSlot * (root.barLabel !== "" ? 2 : 1)
    dimmed: !root.primary && !root.hasRequest
    active: root.hasRequest || Model.lowBattery(phone.primaryBattery)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton && root.primary) phone.sendFiles(root.primary.id)
      else if (b === Qt.MiddleButton && root.primary) phone.ring(root.primary.id)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.primary) return
        if (t === "r" || t === "R") phone.ring(root.primary.id)
        else if (t === "f" || t === "F") phone.sendFiles(root.primary.id)
        else if (t === "c" || t === "C") phone.sendClipboard(root.primary.id)
        else if (t === "p" || t === "P") phone.ping(root.primary.id)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.primary ? root.primary.name : "Phone"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.primary ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.primary ? Model.deviceGlyph(root.primary.type) : Model.GLYPH.phone
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: phone.serviceKnown
                checked: phone.serviceActive
                foreground: root.foreground
                onToggled: phone.setServiceRunning(!phone.serviceActive)
                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: phone.serviceActive ? "Stop rust-connect" : "Start rust-connect"
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          PlainLabel {
            visible: phone.actionStatus !== "" || (phone.lastError !== "" && !phone.streamUp)
            width: parent.width
            text: phone.actionStatus !== "" ? phone.actionStatus : phone.lastError
            color: phone.actionStatus === "" ? root.urgent : root.dim
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PlainLabel {
            visible: !phone.streamUp && !phone.serviceKnown
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            text: "The rust-connect user service is not installed. Install it from github.com/georgeglarson/rust-connect (packaging/install-user-service.sh), and allow ports 1714–1764 (TCP and UDP) through ufw."
          }

          // Pairing requests ---------------------------------------------
          Repeater {
            model: phone.requests
            RequestCard {
              required property var modelData
              width: column.width
              device: modelData
            }
          }

          // Quick actions for the connected phone ------------------------
          Flow {
            visible: root.primary !== null
            width: parent.width
            spacing: Style.space(8)
            ActionChip { glyph: Model.GLYPH.ring; label: "Ring"; onActivated: phone.ring(root.primary.id) }
            ActionChip { glyph: Model.GLYPH.sendFile; label: "Send files"; onActivated: phone.sendFiles(root.primary.id) }
            ActionChip { glyph: Model.GLYPH.sendClipboard; label: "Send clipboard"; onActivated: phone.sendClipboard(root.primary.id) }
            ActionChip { glyph: Model.GLYPH.ping; label: "Ping"; onActivated: phone.ping(root.primary.id) }
          }

          PanelSeparator { visible: phone.devices.length > 0; foreground: root.foreground }

          Column {
            visible: phone.devices.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "Devices"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: phone.devices
              DeviceRow {
                required property var modelData
                width: column.width
                device: modelData
              }
            }
          }

          PlainLabel {
            visible: phone.streamUp && phone.devices.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            text: "Open KDE Connect on your phone while it is on the same network. If nothing shows up, check that ufw allows ports 1714–1764."
          }
        }
      }
    }
  }

  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component ActionChip: CursorSurface {
    id: chip
    property string glyph: ""
    property string label: ""
    signal activated()
    foreground: root.foreground
    bordered: true
    hasCursor: chipMouse.containsMouse
    opacity: phone.busy ? 0.6 : 1.0
    implicitWidth: chipRow.implicitWidth + Style.space(20)
    implicitHeight: chipRow.implicitHeight + Style.space(12)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      PlainLabel { text: chip.glyph; font.pixelSize: Style.font.icon; anchors.verticalCenter: parent.verticalCenter }
      PlainLabel { text: chip.label; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
  }

  component RequestCard: CursorSurface {
    id: card
    property var device: null
    foreground: root.foreground
    bordered: true
    current: true
    implicitHeight: cardCol.implicitHeight + Style.space(20)

    ColumnLayout {
      id: cardCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(6)

      PlainLabel {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: (card.device ? card.device.name : "") + " wants to pair"
      }
      PlainLabel {
        visible: card.device && card.device.verificationKey !== ""
        Layout.fillWidth: true
        color: root.dim
        font.pixelSize: Style.font.bodySmall
        text: "Check that the phone shows the same code:"
      }
      PlainLabel {
        visible: card.device && card.device.verificationKey !== ""
        text: card.device ? card.device.verificationKey : ""
        font.pixelSize: Style.font.heading
        font.letterSpacing: 2
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Item { Layout.fillWidth: true }
        ActionChip { glyph: Model.GLYPH.unpair; label: "Decline"; onActivated: phone.rejectPair(card.device.id) }
        ActionChip { glyph: Model.GLYPH.pair; label: "Accept"; onActivated: phone.acceptPair(card.device.id) }
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: row
    property var device: null
    foreground: root.foreground
    hasCursor: rowMouse.containsMouse
    implicitHeight: rowLayout.implicitHeight + Style.spacing.rowPaddingX

    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

    RowLayout {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      PlainLabel {
        text: row.device ? Model.deviceGlyph(row.device.type) : ""
        font.pixelSize: Style.font.icon
        opacity: row.device && row.device.reachable ? 1.0 : 0.5
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        PlainLabel {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: row.device ? row.device.name : ""
        }
        PlainLabel {
          Layout.fillWidth: true
          elide: Text.ElideRight
          color: root.dim
          font.pixelSize: Style.font.caption
          text: row.device ? Model.stateText(row.device, phone.battery(row.device.id)) : ""
        }
      }

      PanelActionButton {
        visible: row.device && !row.device.paired && !row.device.pairRequested && !row.device.pairing
        iconText: Model.GLYPH.pair
        tooltipText: "Pair"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: phone.pair(row.device.id)
      }
      PanelActionButton {
        visible: row.device && row.device.paired
        iconText: Model.GLYPH.unpair
        tooltipText: "Unpair"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: phone.unpair(row.device.id)
      }
    }
  }
}
