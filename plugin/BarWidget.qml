import QtQuick
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "__ROMULUX_MENU_ID__"

  readonly property real logoAspect: logo.implicitHeight > 0 ? logo.implicitWidth / logo.implicitHeight : 1.45
  readonly property real logoSize: Math.max(10, (root.bar ? root.bar.barSize : 26) * 0.78)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7.5
    fixedWidth: root.vertical ? -1 : root.logoSize * root.logoAspect + Style.spaceReal(7.5) * 2
    fixedHeight: root.vertical ? root.logoSize + Style.spaceReal(6) * 2 : -1
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle __ROMULUX_MENU_ID__ '{\"menu\":\"root\"}'")
    }

    Image {
      id: logo
      anchors.centerIn: parent
      source: Qt.resolvedUrl("logo.png")
      height: root.logoSize
      width: height * root.logoAspect
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
      antialiasing: true
    }
  }
}
