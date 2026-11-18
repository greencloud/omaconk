import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "local.system-monitor"

  property bool opened: false
  property var readings: null
  property bool sampleFailed: false
  property string publicAddress: ""
  property bool popoutSwitchClosing: false
  readonly property string collector: decodeURIComponent(Qt.resolvedUrl("metrics.py").toString().replace(/^file:\/\//, ""))
  readonly property var temperatureRows: {
    const sensors = readings ? readings.temperatures : {}
    const names = ["CPU", "GPU", ...Object.keys(sensors).filter(key => key !== "CPU" && key !== "GPU")]
    if (!names.some(name => /^(nvme|hwmon)/.test(name))) names.push("NVMe")
    return names.map(name => [name, name in sensors ? format(sensors[name], 1) + " °C" : strings.t("unavailable")])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { if (bar) opened = true }
  function close() { opened = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(() => root.popoutSwitchClosing = false)
  }

  function format(value, decimals) {
    return Commons.I18n.formatNumber(value, decimals)
  }

  function size(kib) {
    return kib >= 1048576 ? format(kib / 1048576, 1) + " GiB" : format(kib / 1024, 0) + " MiB"
  }

  function usage(pair) {
    if (!pair[1]) return strings.t("noSwap")
    return size(pair[0]) + " / " + size(pair[1]) + " · " + format(100 * pair[0] / pair[1], 0) + "%"
  }

  function processLabel(row) {
    return row.name || "—"
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    tooltipText: strings.t("title")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        if (root.opened) root.close()
        else root.open()
      }
    }
  }

  Timer {
    interval: 3000
    repeat: true
    triggeredOnStart: true
    running: root.opened
    onTriggered: if (!sample.running) sample.running = true
  }

  Process {
    id: sample
    command: ["python3", root.collector]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.readings = JSON.parse(text)
          root.sampleFailed = false
        } catch (_) {
          root.readings = null
          root.sampleFailed = true
        }
      }
    }
  }

  Process {
    id: lookup
    command: ["python3", root.collector, "--public-ip"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.publicAddress = JSON.parse(text) || strings.t("unavailable")
        } catch (_) {
          root.publicAddress = strings.t("unavailable")
        }
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.body
  }

  component Metric: RowLayout {
    property alias caption: keyLabel.text
    property alias value: valueLabel.text

    Layout.fillWidth: true
    spacing: Commons.Style.space(12)

    Label {
      id: keyLabel
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
    Label {
      id: valueLabel
      Layout.maximumWidth: Commons.Style.space(290)
      horizontalAlignment: Text.AlignRight
      wrapMode: Text.WrapAnywhere
    }
  }

  component Section: Rectangle {
    default property alias entries: rows.data
    readonly property int inset: Commons.Style.space(9)

    Layout.fillWidth: true
    implicitWidth: rows.implicitWidth + inset * 2
    implicitHeight: rows.implicitHeight + inset * 2
    color: "transparent"
    radius: Commons.Style.space(5)
    border.width: 1
    border.color: Commons.Util.alpha(Commons.Color.popups.text, 0.22)

    ColumnLayout {
      id: rows
      anchors.fill: parent
      anchors.margins: parent.inset
      spacing: Commons.Style.space(5)
    }
  }

  Ui.KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: loadedContent
    contentWidth: fittedContentWidth(Commons.Style.space(510))
    contentHeight: fittedContentHeight(loadedContentHeight)

    content: Flickable {
      Keys.onEscapePressed: root.close()
      anchors.fill: parent
      implicitHeight: details.implicitHeight
      contentHeight: details.implicitHeight
      contentWidth: width
      clip: true
      interactive: contentHeight > height

      ColumnLayout {
        id: details
        width: parent.width
        spacing: Commons.Style.space(8)

        Label {
          text: strings.t("title")
          font.bold: true
        }
        Label {
          visible: !root.readings
          text: strings.t(root.sampleFailed ? "unavailable" : "waiting")
        }
        Section {
          visible: !!root.readings
          Metric {
            caption: strings.t("cpu")
            value: root.readings ? root.format(root.readings.cpu, 1) + "%" : ""
          }
          Metric {
            caption: strings.t("load")
            value: root.readings ? root.readings.loads.map(value => root.format(value, 2)).join(" / ") : ""
          }
        }

        Section {
          visible: !!root.readings
          Metric {
            caption: strings.t("ram")
            value: root.readings ? root.usage(root.readings.ram) : ""
          }
        }

        Section {
          visible: !!root.readings
          Metric {
            caption: strings.t("swap")
            value: root.readings ? root.usage(root.readings.swap) : ""
          }
        }

        Section {
          Ui.PanelSectionHeader { text: strings.t("temperatures") }
          Repeater {
            model: root.temperatureRows
            Metric {
              required property var modelData
              caption: modelData[0]
              value: modelData[1]
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: !!root.readings
          spacing: Commons.Style.space(8)

          Section {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 1
            Ui.PanelSectionHeader { text: strings.t("topCpu") }
            Repeater {
              model: root.readings ? root.readings.topCpu : []
              Metric {
                required property var modelData
                caption: root.processLabel(modelData)
                value: root.format(modelData.cpu, 1) + "%"
              }
            }
          }
          Section {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 1
            Ui.PanelSectionHeader { text: strings.t("topRam") }
            Repeater {
              model: root.readings ? root.readings.topRam : []
              Metric {
                required property var modelData
                caption: root.processLabel(modelData)
                value: root.size(modelData.ram)
              }
            }
          }
        }

        Section {
          Ui.PanelSectionHeader { text: strings.t("network") }
          Metric {
            caption: strings.t("dns")
            value: root.readings && root.readings.dns.length ? root.readings.dns.join("\n") : "—"
          }
          Metric {
            visible: root.publicAddress !== "" || lookup.running
            caption: strings.t("public")
            value: lookup.running ? strings.t("checking") : root.publicAddress
          }
          Ui.Button {
            Layout.alignment: Qt.AlignRight
            text: strings.t(root.publicAddress ? "refresh" : "lookup")
            enabled: !lookup.running
            bordered: true
            focusable: true
            onClicked: lookup.running = true
          }
        }
      }
    }
  }
}
