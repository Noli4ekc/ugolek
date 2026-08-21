import SwiftUI

struct FriendsView: View {
    var body: some View {
        ContentUnavailableView(
            "Друзья",
            systemImage: "person.2.fill",
            description: Text("Список друзей для продления огоньков")
        )
    }
}
