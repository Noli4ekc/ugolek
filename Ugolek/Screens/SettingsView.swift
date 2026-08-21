import SwiftUI

struct SettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Настройки",
            systemImage: "gearshape.fill",
            description: Text("Текст сообщения, время запуска и переключатели")
        )
    }
}
