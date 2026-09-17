import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: page

    property var payload: ({})
    property bool loading: false
    property string errorText: ""
    property int warningRemaining: 50
    property int criticalRemaining: 20
    property var subscription: payload && payload.subscription ? payload.subscription : null
    property var apiUsage: payload && payload.api ? payload.api : null
    property int subPage: subscription ? 0 : 1
    signal refreshRequested()
    signal configureRequested()

    function percentText(value) {
        return value === null || value === undefined ? "—" : Math.round(Number(value)) + "%";
    }

    function tokenText(value) {
        var n = Number(value) || 0;
        if (n >= 1000000)
            return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "K";
        return String(n);
    }

    function resetText(epoch) {
        if (!epoch)
            return "—";
        var date = new Date(Number(epoch) * 1000);
        return Qt.formatDateTime(date, "MM-dd hh:mm");
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 9

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 1
                PlasmaComponents3.Label {
                    text: "CODEX"
                    color: "#10A37F"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 2
                }
                PlasmaComponents3.Label {
                    text: subscription && apiUsage ? "订阅额度与 API 用量" : apiUsage ? "OpenAI API 用量" : "Codex 本地会话状态"
                    opacity: 0.7
                    font.pixelSize: 11
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 9; height: 9; radius: 5
                color: errorText.length > 0 ? Kirigami.Theme.negativeTextColor : loading ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor
            }
        }

        QQC2.TabBar {
            visible: subscription && apiUsage
            Layout.fillWidth: true
            currentIndex: page.subPage
            onCurrentIndexChanged: page.subPage = currentIndex
            QQC2.TabButton { text: "订阅额度" }
            QQC2.TabButton { text: "API 用量" }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 9
                visible: subscription && (!apiUsage || page.subPage === 0)

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 150
                    Layout.preferredHeight: 150
                    UsageRing {
                        anchors.fill: parent
                        usage: subscription && subscription.primary ? Math.max(0, Math.min(1, (100 - Number(subscription.primary.used_percent)) / 100)) : 0
                        ringColor: subscription && subscription.primary && 100 - Number(subscription.primary.used_percent) <= page.criticalRemaining ? Kirigami.Theme.negativeTextColor : subscription && subscription.primary && 100 - Number(subscription.primary.used_percent) <= page.warningRemaining ? Kirigami.Theme.neutralTextColor : "#10A37F"
                        lineWidth: 10
                        centerText: subscription && subscription.primary ? page.percentText(100 - Number(subscription.primary.used_percent)) : "—"
                        subText: "5 小时剩余"
                        alert: subscription && subscription.primary && 100 - Number(subscription.primary.used_percent) <= page.criticalRemaining
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard {
                        title: "5 小时剩余"
                        value: subscription && subscription.primary ? page.percentText(100 - Number(subscription.primary.used_percent)) : "—"
                    }
                    StatCard {
                        title: "每周剩余"
                        value: subscription && subscription.secondary ? page.percentText(100 - Number(subscription.secondary.used_percent)) : "—"
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard {
                        title: "上下文"
                        value: subscription ? page.tokenText(subscription.context.used) + " / " + page.tokenText(subscription.context.limit) : "—"
                    }
                    StatCard {
                        title: "会话 Token"
                        value: subscription ? page.tokenText(subscription.tokens.total) : "—"
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    radius: 10
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 2
                        PlasmaComponents3.Label { text: "模型：" + (subscription ? subscription.model || "未知" : "—"); Layout.fillWidth: true; elide: Text.ElideRight }
                        PlasmaComponents3.Label { text: "计划：" + (subscription ? subscription.planType || "未知" : "—"); Layout.fillWidth: true; elide: Text.ElideRight }
                        PlasmaComponents3.Label { text: "5 小时重置：" + (subscription && subscription.primary ? page.resetText(subscription.primary.resets_at) : "—"); Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.75 }
                        PlasmaComponents3.Label { text: "每周重置：" + (subscription && subscription.secondary ? page.resetText(subscription.secondary.resets_at) : "—"); Layout.fillWidth: true; elide: Text.ElideRight; opacity: 0.75 }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 9
                visible: apiUsage && (!subscription || page.subPage === 1)
                Item { Layout.preferredHeight: 12 }
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "$" + (apiUsage ? Number(apiUsage.today.cost).toFixed(2) : "0.00")
                    font.pixelSize: 42
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "今日 API 费用"
                    opacity: 0.7
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard { title: "本月费用"; value: apiUsage ? "$" + Number(apiUsage.month.cost).toFixed(2) : "—" }
                    StatCard { title: "今日请求"; value: apiUsage ? String(apiUsage.today.tokens.requests) : "—" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard { title: "今日输入"; value: apiUsage ? page.tokenText(apiUsage.today.tokens.input) : "—" }
                    StatCard { title: "今日输出"; value: apiUsage ? page.tokenText(apiUsage.today.tokens.output) : "—" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StatCard { title: "本月输入"; value: apiUsage ? page.tokenText(apiUsage.month.tokens.input) : "—" }
                    StatCard { title: "缓存输入"; value: apiUsage ? page.tokenText(apiUsage.month.tokens.cachedInput) : "—" }
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width * 0.86
                visible: !subscription && !apiUsage
                Kirigami.Icon {
                    source: errorText.length > 0 ? "dialog-error" : "dialog-information"
                    implicitWidth: 48; implicitHeight: 48
                    Layout.alignment: Qt.AlignHCenter
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: errorText.length > 0 ? errorText : "未找到 Codex 会话状态。请运行一次 Codex，或在设置中配置 OpenAI Admin API Key 文件。"
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            PlasmaComponents3.Button { text: loading ? "刷新中…" : "立即刷新"; enabled: !loading; onClicked: page.refreshRequested() }
            PlasmaComponents3.Button { text: "设置"; onClicked: page.configureRequested() }
        }
    }
}
