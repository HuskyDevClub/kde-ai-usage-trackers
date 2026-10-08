// Shared file: edit shared/contents/config/config.qml, then run `./sync-shared.sh`.
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("@title", "General")
        icon: "configure"
        source: "configGeneral.qml"
    }
}
