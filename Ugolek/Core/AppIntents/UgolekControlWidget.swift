import AppIntents
import WidgetKit

// Кнопка «🔥 Продлить» в Пункте управления (Control Center), iOS 18+
// Пользователь добавляет её через Настройки → Пункт управления → Уголёк
@available(iOS 18.0, *)
struct UgolekControlWidget: ControlWidget {
    static let kind = "com.ugolek.streak-button"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            ControlWidgetButton(action: MaintainStreaksIntent()) {
                Label("Продлить", systemImage: "flame.fill")
            }
        )
        .displayName("Продлить огоньки")
        .description("Запустить рассылку сообщений друзьям в TikTok")
    }
}
