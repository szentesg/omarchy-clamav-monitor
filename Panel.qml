import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.szentesg.clamav-monitor"
  ipcTarget: "io.github.szentesg.clamav-monitor"

  readonly property int refreshIntervalSec: setting("refreshIntervalSec", 60)
  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.szentesg.clamav-monitor/bin/status.sh"
  // Bounds status.sh's stdout even if the script ever regresses and emits
  // an unbounded amount of data; 10 recent entries fit comfortably under this.
  readonly property int maxStatusOutputBytes: 65536

  property var clamStatus: ({
    lastUpdateEpoch: 0,
    clamdActive: false,
    clamonaccActive: false,
    freshclamActive: false,
    total: 0,
    activeCount: 0,
    recent: [],
    logPath: "/var/log/clamav/clamonacc.log",
    logReadable: false
  })

  // recent[0] is the most recent detection (status.sh emits newest-first).
  readonly property real latestEventEpoch: clamStatus.recent.length > 0 ? clamStatus.recent[0].whenEpoch : 0
  // Advances to latestEventEpoch only when the panel is opened while no
  // detection's file is still present, i.e. once you've actually seen that
  // everything is resolved. An active threat is never dismissed just by
  // opening the panel.
  property real acknowledgedEpoch: 0

  readonly property bool hasDetections: clamStatus.activeCount > 0 || latestEventEpoch > acknowledgedEpoch

  function statusHeadline() {
    if (clamStatus.activeCount > 0) {
      return clamStatus.activeCount + " active detection" + (clamStatus.activeCount === 1 ? "" : "s")
    }
    return "No active detections"
  }

  onOpenedChanged: {
    if (opened && clamStatus.activeCount === 0) acknowledgedEpoch = latestEventEpoch
  }
  readonly property string icon: hasDetections ? "" : ""

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function openLog() {
    if (root.bar) root.bar.run("omarchy-launch-editor " + Util.shellQuote(clamStatus.logPath))
  }

  function formatLastUpdate() {
    if (!clamStatus.lastUpdateEpoch) return "Unknown"
    var diffSec = Math.floor(Date.now() / 1000 - clamStatus.lastUpdateEpoch)
    if (diffSec < 0) diffSec = 0
    if (diffSec < 60) return "Just now"
    if (diffSec < 3600) return Math.floor(diffSec / 60) + " min ago"
    if (diffSec < 86400) return Math.floor(diffSec / 3600) + " h ago"
    return Math.floor(diffSec / 86400) + " d ago"
  }

  // Renders in whatever date/time format the OS locale is configured with
  // (LC_TIME / localectl), rather than a hardcoded string.
  function formatDetectionTime(epoch) {
    if (!epoch) return "unknown time"
    return new Date(epoch * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["bash", root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.length > root.maxStatusOutputBytes) {
          // Keep the last known good status rather than parsing a
          // suspiciously oversized payload.
          return
        }
        try {
          root.clamStatus = JSON.parse(text)
        } catch (e) {
          // Keep the last known good status if the script output is malformed
          // (e.g. mid-write) rather than blanking the panel.
        }
      }
    }
  }

  // Background refresh while closed, faster refresh while the panel is open.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: !root.opened
    repeat: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.hasDetections ? root.bar.urgent : root.bar.foreground
    slotSize: Style.bar.iconSlot
    tooltipText: "ClamAV: " + root.statusHeadline()
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · title/status ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.icon
            color: root.hasDetections ? root.bar.urgent : root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "ClamAV"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.statusHeadline()
              color: root.hasDetections ? root.bar.urgent : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Status rows ----------
        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          RowLayout {
            width: parent.width
            Text {
              text: "Last updated"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.formatLastUpdate()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          RowLayout {
            width: parent.width
            Text {
              text: "On-access monitoring"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.clamStatus.clamonaccActive ? "Active" : "Stopped"
              color: root.clamStatus.clamonaccActive ? root.bar.foreground : root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          RowLayout {
            width: parent.width
            Text {
              text: "Auto-update"
              color: root.bar.foreground
              opacity: 0.6
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.clamStatus.freshclamActive ? "Active" : "Stopped"
              color: root.clamStatus.freshclamActive ? root.bar.foreground : root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---------- Recent detections ----------
        PanelSeparator { foreground: root.bar.foreground }

        PanelSectionHeader {
          text: "RECENT DETECTIONS"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          visible: root.clamStatus.recent.length === 0
          width: parent.width
          text: root.clamStatus.logReadable
            ? "No detections in the log yet."
            : "The log isn't readable (permission missing)."
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.clamStatus.recent.length > 0

          Repeater {
            model: root.clamStatus.recent

            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(1)

              Text {
                text: modelData.signature
                textFormat: Text.PlainText
                color: modelData.present === false ? Qt.darker(root.bar.foreground, 1.4) : root.bar.urgent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.formatDetectionTime(modelData.whenEpoch)
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width
              }

              Text {
                text: modelData.path
                textFormat: Text.PlainText
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                width: parent.width
              }

              Text {
                visible: modelData.present === false
                text: "Quarantined or removed"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.italic: true
                width: parent.width
              }
            }
          }
        }

        // ---------- Open full log (only when there are more than 10) ----------
        Button {
          visible: root.clamStatus.total > 10
          width: parent.width
          text: "Open log (" + root.clamStatus.total + " detections total)"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.openLog()
        }
      }
    }
  }
}
