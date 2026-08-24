import AppIntents
#if !targetEnvironment(simulator)
// Control Center controls don't exist in the Simulator runtime — the types
// only resolve in device builds. Guard keeps the simulator compile-check green.
import WidgetKit

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
