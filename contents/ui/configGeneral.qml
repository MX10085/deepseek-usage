import QtQuick 2.15
import QtQuick.Controls 2.15 as QQC2
import QtQuick.Layouts 1.15
import org.kde.kirigami 2.20 as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_apiKey: apiKeyField.text
    property alias cfg_refreshInterval: refreshSpin.value
    property alias cfg_lowThreshold: lowSpin.value
    property alias cfg_fullBalanceTarget: fullBalanceSpin.value
    property alias cfg_warnPercent: warnSpin.value
    property alias cfg_criticalPercent: critSpin.value
    property string cfg_compactMode: "balance"
    property string cfg_defaultPage: "deepseek"
    property string cfg_codexMode: "auto"
    property alias cfg_codexHome: codexHomeField.text
    property alias cfg_openaiAdminKeyFile: adminKeyFileField.text
    property alias cfg_codexRefreshInterval: codexRefreshSpin.value
    property alias cfg_codexWarnRemaining: codexWarnSpin.value
    property alias cfg_codexCriticalRemaining: codexCriticalSpin.value

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
            id: fullBalanceSpin
            Kirigami.FormData.label: "100% 基准余额（元）："
            from: 1
            to: 10000
            stepSize: 10
            editable: true
            value: 100
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

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
        }

        QQC2.ComboBox {
            id: defaultPageCombo
            Kirigami.FormData.label: "默认页面："
            model: ["DeepSeek", "Codex"]
            Component.onCompleted: currentIndex = cfg_defaultPage === "codex" ? 1 : 0
            onActivated: cfg_defaultPage = currentIndex === 1 ? "codex" : "deepseek"
        }

        QQC2.ComboBox {
            id: codexModeCombo
            Kirigami.FormData.label: "Codex 数据来源："
            model: ["自动检测", "Codex 订阅", "OpenAI API", "同时显示"]
            Component.onCompleted: {
                var values = ["auto", "subscription", "api", "both"];
                currentIndex = Math.max(0, values.indexOf(cfg_codexMode));
            }
            onActivated: cfg_codexMode = ["auto", "subscription", "api", "both"][currentIndex]
        }

        QQC2.TextField {
            id: codexHomeField
            Kirigami.FormData.label: "Codex 数据目录："
            Layout.fillWidth: true
            placeholderText: "留空使用 ~/.codex"
        }

        QQC2.TextField {
            id: adminKeyFileField
            Kirigami.FormData.label: "Admin Key 文件："
            Layout.fillWidth: true
            placeholderText: "例如 ~/.config/openai/admin-key"
        }

        QQC2.SpinBox {
            id: codexRefreshSpin
            Kirigami.FormData.label: "Codex 刷新间隔（秒）："
            from: 10
            to: 3600
            stepSize: 5
            value: 15
        }

        QQC2.SpinBox {
            id: codexWarnSpin
            Kirigami.FormData.label: "额度警告阈值（剩余 %）："
            from: 1
            to: 99
            stepSize: 5
            value: 50
        }

        QQC2.SpinBox {
            id: codexCriticalSpin
            Kirigami.FormData.label: "额度严重阈值（剩余 %）："
            from: 1
            to: 99
            stepSize: 5
            value: 20
        }

        QQC2.Label {
            Kirigami.FormData.label: "OpenAI API："
            text: "API 统计需要组织 Owner 创建的 Admin API Key。密钥文件应只允许当前用户读取；也可通过 OPENAI_ADMIN_KEY 环境变量提供。"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            opacity: 0.7
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
