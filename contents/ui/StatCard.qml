import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: card

    property string title: ""
    property string value: ""

    color: Qt.rgba(Kirigami.Theme.textColor.r,
                   Kirigami.Theme.textColor.g,
                   Kirigami.Theme.textColor.b, 0.08)
    radius: 8
    Layout.fillWidth: true
    Layout.preferredHeight: 46

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 7
        anchors.bottomMargin: 7
        spacing: 1

        PlasmaComponents3.Label {
            text: card.title
            font.pixelSize: 10
            opacity: 0.7
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        PlasmaComponents3.Label {
            text: card.value
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
