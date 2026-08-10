import QtQuick 2.15

Item {
    id: root

    property var values: [] // 按时间从旧到新的数值数组
    property var labels: [] // 与 values 等长的标签（如 "8/3"）
    property color barColor: "#FF8014"
    property color todayColor: "#4D6BFE"
    property int barCount: Math.max(1, root.values.length)
    property real barSpacingFactor: 0.55
    property int hoverIndex: -1
    readonly property real maxValue: {
        var m = 0;
        for (var i = 0; i < root.values.length; i++) {
            var v = Number(root.values[i]) || 0;
            if (v > m)
                m = v;

        }
        return m;
    }

    onValuesChanged: cvs.requestPaint()

    Canvas {
        id: cvs

        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var n = root.values.length;
            if (n === 0)
                return ;

            var w = width;
            var h = height;
            var slot = w / n;
            var barW = Math.max(2, slot * root.barSpacingFactor);
            var maxV = root.maxValue > 0 ? root.maxValue : 1;
            for (var i = 0; i < n; i++) {
                var v = Math.max(0, Number(root.values[i]) || 0);
                var bh = Math.max(2, h * (v / maxV));
                var x = i * slot + (slot - barW) / 2;
                var r = Math.min(2.5, barW / 2, bh / 2);
                ctx.fillStyle = i === n - 1 ? root.todayColor : root.barColor;
                ctx.beginPath();
                ctx.moveTo(x, h);
                ctx.lineTo(x, h - bh + r);
                ctx.arcTo(x, h - bh, x + barW / 2, h - bh, r);
                ctx.arcTo(x + barW, h - bh, x + barW, h - bh + r, r);
                ctx.lineTo(x + barW, h);
                ctx.closePath();
                ctx.fill();
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: {
            root.hoverIndex = Math.floor(mouse.x / (width / Math.max(1, root.values.length)));
        }
        onExited: root.hoverIndex = -1
    }

    Rectangle {
        property real slotW: width > 0 ? root.width / Math.max(1, root.values.length) : 0

        visible: root.hoverIndex >= 0 && root.hoverIndex < root.values.length
        z: 2
        width: tipText.width + 14
        height: tipText.height + 6
        radius: 5
        color: "#E6000000"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        x: Math.max(0, Math.min(root.width - width, root.hoverIndex * slotW + slotW / 2 - width / 2))
        y: 0

        Text {
            id: tipText

            anchors.centerIn: parent
            text: {
                if (root.hoverIndex < 0 || root.hoverIndex >= root.values.length)
                    return "";

                var label = root.hoverIndex < root.labels.length ? root.labels[root.hoverIndex] : "";
                var val = Number(root.values[root.hoverIndex]) || 0;
                return (label.length > 0 ? label + "  " : "") + "¥" + val.toFixed(2);
            }
            color: "#FFFFFF"
            font.pixelSize: 10
        }

    }

}
