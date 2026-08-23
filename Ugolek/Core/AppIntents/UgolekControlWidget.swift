import AppIntents

// Кнопка «🔥 Продлить» в Пункте управления (Control Center), iOS 18+
// Пользователь добавляет её через Настройки → Пункт управления → Уголёк
// Условная компиляция: ControlWidget доступен только в Xcode 16+ (iOS 18 SDK)
#if compiler(>=6.0)
import WidgetKit

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
#endif
