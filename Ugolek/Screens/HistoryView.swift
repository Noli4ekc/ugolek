import SwiftUI

struct HistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "История",
            systemImage: "clock.arrow.circlepath",
            description: Text("Здесь будет история прогонов и статистика")
        )
    }
}
