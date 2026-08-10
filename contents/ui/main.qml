import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.notification
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    // 只刷新时间，不覆盖起点余额，百分比保持稳定

    id: root

    // ---------- 配置 ----------
    property string apiKey: plasmoid.configuration.apiKey
    property int refreshSec: Math.max(30, plasmoid.configuration.refreshInterval || 60)
    property real lowThreshold: plasmoid.configuration.lowThreshold === undefined ? 10 : plasmoid.configuration.lowThreshold
    property int warnPercent: plasmoid.configuration.warnPercent === undefined ? 50 : Math.max(1, Math.min(99, plasmoid.configuration.warnPercent))
    property int criticalPercent: plasmoid.configuration.criticalPercent === undefined ? 15 : Math.max(1, Math.min(99, plasmoid.configuration.criticalPercent))
    property string compactMode: plasmoid.configuration.compactMode === "percent" ? "percent" : "balance"
    property bool notifiedLow: false
    // ---------- 运行状态 ----------
    property var infos: []
    property var firstInfo: null
    property bool isAvailable: false
    property string state: "idle" // idle | loading | ok | error | nokey
    property string lastError: ""
    property string lastUpdateText: ""
    property var snapshots: []
    property bool booted: false
    property real todayUsage: 0
    property real weekUsage: 0
    property real totalUsage: 0
    property var dailySeries: [] // 近 7 日每日消耗（旧→新）
    property var dailyLabels: [] // 近 7 日日期标签（旧→新）
    readonly property real balanceNow: firstInfo ? parseFloat(firstInfo.total_balance) : 0
    readonly property string curSymbol: firstInfo ? (firstInfo.currency === "CNY" ? "¥" : firstInfo.currency === "USD" ? "$" : firstInfo.currency + " ") : "¥"
    readonly property string balanceText: state === "ok" ? balanceNow.toFixed(2) : state === "nokey" ? "未设置 Key" : state === "error" ? "获取失败" : "..."
    readonly property bool lowBalance: state === "ok" && firstInfo && balanceNow >= 0 && balanceNow < lowThreshold
    readonly property bool hasData: firstInfo !== null && firstInfo !== undefined
    // ---------- 用量百分比 ----------
    readonly property real startBalance: snapshots.length > 0 ? snapshots[0].b : balanceNow
    readonly property real remainingFrac: startBalance > 0 ? Math.max(0, Math.min(1, balanceNow / startBalance)) : 1
    readonly property real usagePercent: startBalance > 0 ? Math.max(0, Math.min(100, (startBalance - balanceNow) / startBalance * 100)) : 0
    readonly property real warnFrac: warnPercent / 100
    readonly property real critFrac: criticalPercent / 100
    readonly property color gaugeColor: state !== "ok" ? Kirigami.Theme.neutralTextColor : (lowBalance || remainingFrac <= critFrac) ? Kirigami.Theme.negativeTextColor : remainingFrac <= warnFrac ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
    // 圆环配色：充足=DeepSeek 蓝，过半=黄/橙，低余额=红，出错/无 Key=警示色
    readonly property color ringDisplayColor: {
        if (state === "error" || state === "nokey")
            return Kirigami.Theme.neutralTextColor;

        if (lowBalance || remainingFrac <= critFrac)
            return Kirigami.Theme.negativeTextColor;

        if (remainingFrac <= warnFrac)
            return Kirigami.Theme.neutralTextColor;

        return accentColor;
    }
    // ---------- 状态横幅 ----------
    readonly property color accentColor: "#4D6BFE"
    readonly property string bannerText: {
        if (state === "nokey")
            return "未设置 Key，请点击“设置”填写";

        if (state === "error")
            return "获取失败，请稍后重试";

        if (state === "loading" && !hasData)
            return "正在获取余额…";

        if (!isAvailable)
            return "账户当前不可用";

        if (lowBalance)
            return "余额偏低，建议及时充值";

        if (remainingFrac <= warnFrac)
            return "余额尚可，注意用量";

        return "余额充足，放心开工";
    }
    readonly property color bannerColor: {
        if (state === "nokey" || state === "error")
            return Kirigami.Theme.neutralTextColor;

        if (state === "loading" && !hasData)
            return Kirigami.Theme.neutralTextColor;

        if (!isAvailable || lowBalance)
            return Kirigami.Theme.negativeTextColor;

        if (remainingFrac <= warnFrac)
            return Kirigami.Theme.neutralTextColor;

        return Kirigami.Theme.positiveTextColor;
    }
    readonly property color bannerBg: {
        var c = bannerColor;
        return Qt.rgba(c.r, c.g, c.b, 0.16);
    }
    readonly property string tooltipDetail: {
        var lines = [];
        if (state === "ok") {
            lines.push("可用：" + (isAvailable ? "是" : "否"));
            lines.push("剩余：" + (remainingFrac * 100).toFixed(1) + "%");
            lines.push("已用（估算）：" + usagePercent.toFixed(1) + "%");
            lines.push("今日消耗（估算）：" + curSymbol + todayUsage.toFixed(2));
            lines.push("最近更新：" + lastUpdateText);
            lines.push("中键切换：余额/百分比");
        } else if (state === "nokey") {
            lines.push("请在设置中填入 DeepSeek API Key");
        } else if (state === "error") {
            lines.push(lastError);
            lines.push("点击查看详情");
        } else {
            lines.push("正在获取余额...");
        }
        return lines.join("\n");
    }

    // ---------- 快照：用量估算 ----------
    function loadSnapshots() {
        try {
            snapshots = JSON.parse(plasmoid.configuration.snapshots || "[]");
        } catch (e) {
            snapshots = [];
        }
        if (!Array.isArray(snapshots))
            snapshots = [];

    }

    function saveSnapshots() {
        plasmoid.configuration.snapshots = JSON.stringify(snapshots);
    }

    function recordSnapshot() {
        if (!firstInfo)
            return ;

        var now = Date.now();
        var last = snapshots.length > 0 ? snapshots[snapshots.length - 1] : null;
        // 检测到充值/赠送到账：余额明显回升，重置计量起点
        if (last && balanceNow > last.b + 0.01) {
            snapshots = [{
                "t": now,
                "b": balanceNow
            }];
            saveSnapshots();
            return ;
        }
        if (last && now - last.t < 5 * 60 * 1000)
            last.t = now;
        else
            snapshots.push({
            "t": now,
            "b": balanceNow
        });
        while (snapshots.length > 300)snapshots.shift()
        saveSnapshots();
    }

    function startOfToday() {
        var d = new Date();
        d.setHours(0, 0, 0, 0);
        return d.getTime();
    }

    function startOfWeek() {
        var d = new Date();
        d.setHours(0, 0, 0, 0);
        var dow = d.getDay(); // 0=周日
        d.setDate(d.getDate() - (dow === 0 ? 6 : dow - 1)); // 周一起算
        return d.getTime();
    }

    function usageSince(cutoff) {
        if (snapshots.length === 0)
            return 0;

        var base = null;
        for (var i = 0; i < snapshots.length; i++) {
            if (snapshots[i].t >= cutoff) {
                base = snapshots[i].b;
                break;
            }
        }
        if (base === null)
            return 0;

        return Math.max(0, base - balanceNow);
    }

    function refreshUsage() {
        todayUsage = usageSince(startOfToday());
        weekUsage = usageSince(startOfWeek());
        totalUsage = snapshots.length > 0 ? Math.max(0, snapshots[0].b - balanceNow) : 0;
        refreshDailySeries();
    }

    function dayStartAt(offsetDays) {
        var d = new Date();
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() - offsetDays);
        return d.getTime();
    }

    function balanceAt(cutoff) {
        for (var i = 0; i < snapshots.length; i++) {
            if (snapshots[i].t >= cutoff)
                return snapshots[i].b;

        }
        return balanceNow;
    }

    function dailyUsageSeries(count) {
        var out = [];
        for (var k = count - 1; k >= 0; k--) {
            var startB = balanceAt(dayStartAt(k + 1));
            var endB = k === 0 ? balanceNow : balanceAt(dayStartAt(k));
            out.push(Math.max(0, startB - endB));
        }
        return out;
    }

    function dayLabels(count) {
        var out = [];
        for (var k = count - 1; k >= 0; k--) {
            var d = new Date();
            d.setDate(d.getDate() - k);
            out.push((d.getMonth() + 1) + "/" + d.getDate());
        }
        return out;
    }

    function refreshDailySeries() {
        dailySeries = dailyUsageSeries(7);
        dailyLabels = dayLabels(7);
    }

    // ---------- 拉取余额 ----------
    function fetch() {
        if (!apiKey || apiKey.length === 0) {
            state = "nokey";
            return ;
        }
        state = "loading";
        lastError = "";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.deepseek.com/user/balance");
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return ;

            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    infos = resp.balance_infos || [];
                    firstInfo = infos.length > 0 ? infos[0] : null;
                    isAvailable = !!resp.is_available;
                    if (!firstInfo) {
                        state = "error";
                        lastError = "响应中没有余额数据";
                        return ;
                    }
                    recordSnapshot();
                    refreshUsage();
                    lastUpdateText = Qt.formatTime(new Date(), "hh:mm:ss");
                    state = "ok";
                    checkNotifyLow();
                } catch (e) {
                    state = "error";
                    lastError = "响应解析失败：" + e;
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                state = "error";
                lastError = "API Key 无效（" + xhr.status + "）";
            } else {
                state = "error";
                lastError = "请求失败：HTTP " + xhr.status;
            }
        };
        xhr.send();
    }

    function checkNotifyLow() {
        if (lowBalance) {
            if (!notifiedLow) {
                lowNotif.text = "当前余额 " + curSymbol + balanceNow.toFixed(2) + "，低于提醒阈值 " + curSymbol + lowThreshold.toFixed(0) + "，请及时充值。";
                lowNotif.sendEvent();
                notifiedLow = true;
            }
        } else {
            notifiedLow = false;
        }
    }

    function toggleCompactMode() {
        compactMode = compactMode === "percent" ? "balance" : "percent";
        plasmoid.configuration.compactMode = compactMode;
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    Plasmoid.title: "DeepSeek 用量监控"
    Plasmoid.status: (lowBalance || state === "error" || state === "nokey") ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
    toolTipMainText: state === "ok" ? "DeepSeek 余额：" + curSymbol + balanceText : "DeepSeek 用量监控"
    toolTipSubText: tooltipDetail
    Component.onCompleted: {
        loadSnapshots();
        booted = true;
        fetch();
    }

    // ---------- 低余额系统通知 ----------
    Notification {
        id: lowNotif

        eventId: "deepseek-low-balance"
        componentName: "plasmashell"
        title: "DeepSeek 余额不足"
        iconName: "dialog-warning"
        urgency: Notification.HighUrgency
        autoDelete: false
    }

    // ---------- 定时刷新 ----------
    Timer {
        id: refreshTimer

        interval: root.refreshSec * 1000
        repeat: true
        running: root.booted && root.apiKey.length > 0
        onTriggered: root.fetch()
    }

    Connections {
        function onApiKeyChanged() {
            if (root.booted)
                root.fetch();

        }

        function onRefreshIntervalChanged() {
            refreshTimer.restart();
        }

        function onCompactModeChanged() {
            root.compactMode = plasmoid.configuration.compactMode === "percent" ? "percent" : "balance";
        }

        target: plasmoid.configuration
    }

    // ---------- 面板上的紧凑显示：圆形用量环 + 中间余额 ----------
    compactRepresentation: MouseArea {
        id: compactMouse

        implicitWidth: 36
        implicitHeight: 36
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse.button === Qt.MiddleButton ? root.toggleCompactMode() : root.expanded = !root.expanded

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, compactMouse.containsMouse ? 0.22 : 0)

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }

            }

        }

        UsageRing {
            anchors.fill: parent
            usage: root.remainingFrac
            ringColor: root.ringDisplayColor
            lineWidth: 3.5
            centerText: !root.hasData ? (root.state === "nokey" ? "无Key" : root.state === "error" ? "失败" : "...") : root.compactMode === "percent" ? Math.round(root.remainingFrac * 100) + "%" : root.balanceNow.toFixed(1)
            showSub: false
            alert: root.lowBalance
        }

    }

    // ---------- 点击后的完整面板（Codex Status 风格） ----------
    fullRepresentation: Item {
        Layout.minimumWidth: 350
        Layout.minimumHeight: 460
        Layout.preferredWidth: 380
        Layout.preferredHeight: 500

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 9

            // 头部：鲸鱼标 + 标题/副标题 + 状态点
            RowLayout {
                spacing: 10

                Rectangle {
                    implicitWidth: 42
                    implicitHeight: 42
                    radius: 11
                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        anchors.centerIn: parent
                        source: "../images/deepseek-whale.svg"
                        sourceSize.width: 30
                        sourceSize.height: 30
                        fillMode: Image.PreserveAspectFit
                    }

                }

                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter

                    PlasmaComponents3.Label {
                        text: "DEEPSEEK USAGE"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 2
                        color: root.accentColor
                    }

                    PlasmaComponents3.Label {
                        text: "实时读取 DeepSeek 账户余额"
                        font.pixelSize: 12
                        opacity: 0.75
                        elide: Text.ElideRight
                    }

                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: statusDot

                    implicitWidth: 9
                    implicitHeight: 9
                    radius: 4.5
                    color: root.bannerColor
                    Layout.alignment: Qt.AlignVCenter

                    SequentialAnimation on opacity {
                        running: root.state === "ok" && (!root.isAvailable || root.lowBalance)
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 0.25
                            duration: 900
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            to: 1
                            duration: 900
                            easing.type: Easing.InOutSine
                        }

                    }

                }

            }

            // 大圆环：中间剩余百分比，下方余额
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160

                UsageRing {
                    anchors.fill: parent
                    usage: root.remainingFrac
                    ringColor: root.ringDisplayColor
                    lineWidth: 10
                    centerText: root.state === "nokey" || root.state === "error" ? root.balanceText : root.hasData ? Math.round(root.remainingFrac * 100) + "%" : "..."
                    subText: root.state === "nokey" || root.state === "error" ? "" : root.hasData ? root.curSymbol + root.balanceNow.toFixed(2) + " 可用" : ""
                    showSub: root.hasData && root.state === "ok"
                    alert: root.lowBalance
                }

            }

            // 余额金额卡片（DeepSeek 控制台风格）+ 近 7 日消耗柱状图
            Rectangle {
                id: balanceCard

                Layout.fillWidth: true
                Layout.preferredHeight: 66
                radius: 12
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, cardMouse.containsMouse ? 0.12 : 0.07)
                border.width: 1
                border.color: cardMouse.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

                MouseArea {
                    id: cardMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally("https://platform.deepseek.com/usage")
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 14

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true

                        PlasmaComponents3.Label {
                            text: "余额金额 (CNY)"
                            font.pixelSize: 10
                            opacity: 0.65
                        }

                        PlasmaComponents3.Label {
                            text: root.curSymbol + root.balanceNow.toFixed(2)
                            font.pixelSize: 22
                            font.bold: true
                            color: root.state === "error" || root.state === "nokey" ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                        }

                        PlasmaComponents3.Label {
                            text: root.bannerText
                            color: root.bannerColor
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }

                    }

                    UsageBars {
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 46
                        Layout.alignment: Qt.AlignVCenter
                        values: root.dailySeries
                        labels: root.dailyLabels
                        barColor: "#FF8014"
                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }

                }

            }

            // 信息卡片：今日消耗 + 本周消耗
            RowLayout {
                spacing: 8

                StatCard {
                    title: "今日消耗"
                    value: root.curSymbol + root.todayUsage.toFixed(2)
                }

                StatCard {
                    title: "本周消耗"
                    value: root.curSymbol + root.weekUsage.toFixed(2)
                }

            }

            Item {
                Layout.fillHeight: true
            }

            PlasmaComponents3.Label {
                text: "“消耗”按余额变化本地估算，充值到账后自动重新计周期"
                font.pixelSize: 9
                opacity: 0.6
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents3.Button {
                    text: root.state === "loading" ? "刷新中…" : "立即刷新"
                    enabled: root.state !== "loading"
                    onClicked: root.fetch()
                }

                PlasmaComponents3.Button {
                    text: "设置"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }

            }

        }

    }

}
