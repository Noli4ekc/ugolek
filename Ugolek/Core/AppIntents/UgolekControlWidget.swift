import AppIntents
#if !targetEnvironment(simulator)
import WidgetKit

// ControlWidget lives in Control Center — device-only, never available in Simulator SDK.
@available(iOS 18.0, *)
struct UgolekControlWidget: ControlWidget {
    static let kind = "com.ugolek.streak-button"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: MaintainStreaksIntent()) {
                Label("Продлить", systemImage: "flame.fill")
            }
        }
        .displayName("Продлить огоньки")
        .description("Запустить рассылку сообщений друзьям в TikTok")
    }
}
#endif
