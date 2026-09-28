import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.spacer"

  readonly property int authoredSize: settings && settings.size !== undefined ? Number(settings.size) : 12

  // A spacer is a gap like any other, so its size follows the spacing scale and
  // [font] base-size. Rounded here rather than through Style.space(), which
  // floors a positive value at 1 and would turn `size: 0` into one pixel.
  readonly property int span: Math.round(Style.spaceReal(authoredSize))

  implicitWidth: vertical ? barSize : span
  implicitHeight: vertical ? span : barSize
  visible: span > 0
}
