import SwiftUI

struct HomeView: View {
    var body: some View {
        ContentUnavailableView(
            "Уголёк",
            systemImage: "flame.fill",
            description: Text("Здесь появится кнопка «Продлить сейчас» и статус сессии")
        )
    }
}
