import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

Item {
    id: colorProvider
    visible: false

    property bool useCustom: Plasmoid.configuration.useCustomColors
    property color normalColor: useCustom ? Plasmoid.configuration.normalColor : Kirigami.Theme.positiveTextColor
    property color warningColor: useCustom ? Plasmoid.configuration.warningColor : Kirigami.Theme.neutralTextColor
    property color criticalColor: useCustom ? Plasmoid.configuration.criticalColor : Kirigami.Theme.negativeTextColor
}
