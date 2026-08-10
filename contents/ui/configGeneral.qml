import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_lowThreshold: lowSpin.value
    property alias cfg_warnPercent: warnSpin.value
    property alias cfg_criticalPercent: critSpin.value
    property string cfg_compactMode: "balance"

    Kirigami.FormLayout {
        QQC2.TextField {
            id: apiKeyField
            Kirigami.FormData.label: "API Key："
            Layout.fillWidth: true
            placeholderText: "sk-..."
            echoMode: showKey.checked ? TextInput.Normal : TextInput.Password
        }
        QQC2.CheckBox {
            id: showKey
            text: "显示 Key"
        }

        QQC2.SpinBox {
            id: refreshSpin
            Kirigami.FormData.label: "刷新间隔（秒）："
            from: 30
            to: 3600
            stepSize: 30
            editable: true
            value: 60
        }

        QQC2.SpinBox {
            id: lowSpin
            Kirigami.FormData.label: "低余额提醒阈值（元）："
            from: 0
            to: 1000
            stepSize: 5
            editable: true
            value: 10
        }

        QQC2.SpinBox {
            id: warnSpin
            Kirigami.FormData.label: "圆环变黄阈值（剩余百分比 ≤）："
            from: 1
            to: 99
            stepSize: 5
            editable: true
            value: 50
        }

        QQC2.SpinBox {
            id: critSpin
            Kirigami.FormData.label: "圆环变红阈值（剩余百分比 ≤）："
            from: 1
            to: 99
            stepSize: 5
            editable: true
            value: 15
        }

        QQC2.ComboBox {
            id: compactModeCombo
            Kirigami.FormData.label: "任务栏图标显示："
            model: ["余额", "剩余百分比"]

            Component.onCompleted: currentIndex = cfg_compactMode === "percent" ? 1 : 0
            onActivated: cfg_compactMode = currentIndex === 1 ? "percent" : "balance"
        }

        QQC2.Label {
            Kirigami.FormData.label: "说明："
            text: "Token 用量明细没有公开 API，需登录 DeepSeek 控制台查看；面板中的“消耗”按余额变化本地估算。余额接口免费，不消耗 Token。余额低于提醒阈值时会弹系统通知。"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            opacity: 0.7
        }
    }
}
