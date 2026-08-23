import AppIntents

// Кнопка «🔥 Продлить» в Пункте управления (Control Center), iOS 18+
// Пользователь добавляет её через Настройки → Пункт управления → Уголёк
// SKIP_CONTROL_WIDGET: флаг компиляции для CI без iOS 18 SDK (передаётся через project.yml)
#if !SKIP_CONTROL_WIDGET
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
