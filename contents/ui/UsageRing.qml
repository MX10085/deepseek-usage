import QtQuick 2.15
import org.kde.kirigami 2.20 as Kirigami

Item {
    id: root

    property real usage: 0            // 0..1，已用比例
    property real lineWidth: 6
    property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                       Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.14)
    property color ringColor: Kirigami.Theme.highlightColor
    property string centerText: ""
    property string subText: ""
    property bool showSub: true
    property color textColor: Kirigami.Theme.textColor
    property bool animateSweep: true
    property bool alert: false       // 低余额时呼吸光晕

    readonly property real diameter: Math.min(width, height)
    readonly property color ringLight: Qt.lighter(ringColor, 1.4)
    readonly property color ringDark: Qt.darker(ringColor, 1.08)

    // 高亮扫描角度（0..360，从 12 点方向顺时针）
    property real sweep: 0
    // 呼吸脉冲 0..1
    property real pulse: 0

    Canvas {
        id: cvs
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width;
            var h = height;
            var cx = w / 2;
            var cy = h / 2;
            var r = (Math.min(w, h) - root.lineWidth - 2) / 2;
            var p = Math.max(0, Math.min(1, root.usage));
            var startA = -Math.PI / 2;
            var endA = startA + p * Math.PI * 2;

            // 柔和光晕
            var glowAlpha = 0.10 + (root.alert ? 0.32 * root.pulse : 0.05);
            var glow = ctx.createRadialGradient(cx, cy, r - root.lineWidth, cx, cy, r + root.lineWidth + 8);
            glow.addColorStop(0, Qt.rgba(root.ringColor.r, root.ringColor.g, root.ringColor.b, glowAlpha));
            glow.addColorStop(1, Qt.rgba(root.ringColor.r, root.ringColor.g, root.ringColor.b, 0));
            ctx.fillStyle = glow;
            ctx.fillRect(0, 0, w, h);

            // 轨道
            ctx.lineWidth = root.lineWidth;
            ctx.lineCap = "round";
            ctx.strokeStyle = root.trackColor;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.stroke();

            // 用量弧（渐变）
            if (p > 0.005) {
                var grad = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r);
                grad.addColorStop(0, root.ringLight);
                grad.addColorStop(1, root.ringDark);
                ctx.strokeStyle = grad;
                ctx.beginPath();
                ctx.arc(cx, cy, r, startA, endA);
                ctx.stroke();

                // 高光扫过（只出现在用量弧范围内）
                if (root.animateSweep) {
                    var sw = 0.30;
                    var a = -Math.PI / 2 + root.sweep * Math.PI / 180;
                    var segStart = Math.max(startA, a - sw);
                    var segEnd = Math.min(endA, a + sw);
                    if (segEnd > segStart + 0.01) {
                        ctx.strokeStyle = Qt.rgba(root.ringLight.r, root.ringLight.g, root.ringLight.b, 0.85);
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, segStart, segEnd);
                        ctx.stroke();
                    }
                }
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width * 0.74
        spacing: Math.max(0, parent.height * 0.015)

        Text {
            width: parent.width
            text: root.centerText
            color: root.textColor
            font.pixelSize: Math.max(8, Math.min(root.diameter * 0.23, parent.width * 1.75 / Math.max(1, text.length)))
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.showSub && root.subText.length > 0
            text: root.subText
            color: root.textColor
            opacity: 0.75
            font.pixelSize: Math.max(7, Math.min(root.diameter * 0.12, parent.width * 1.25 / Math.max(1, text.length)))
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    Behavior on usage {
        NumberAnimation {
            duration: 900
            easing.type: Easing.OutCubic
        }
    }

    // 高亮扫描
    NumberAnimation on sweep {
        running: root.animateSweep && root.visible
        from: 0
        to: 360
        duration: 5200
        loops: Animation.Infinite
    }

    // 低余额呼吸
    NumberAnimation on pulse {
        running: root.alert
        from: 0
        to: 1
        duration: 1100
        loops: Animation.Infinite
        easing.type: Easing.InOutSine
    }

    onUsageChanged: cvs.requestPaint()
    onRingColorChanged: cvs.requestPaint()
    onTrackColorChanged: cvs.requestPaint()
    onSweepChanged: cvs.requestPaint()
    onPulseChanged: cvs.requestPaint()
}
