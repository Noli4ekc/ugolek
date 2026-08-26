import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var appeared = false

    private let pages: [(icon: String, eyebrow: String, title: String, text: String)] = [
        ("flame.fill", "ЗНАКОМЬСЯ", "Огонёк не гаснет сам", "Уголёк помогает вовремя поддерживать огоньки с друзьями в TikTok."),
        ("person.2.fill", "ТВОЙ КРУГ", "Добавь важных людей", "Собери список друзей и групп. Ты всегда решаешь, кому отправлять сообщения."),
        ("lock.shield.fill", "ЛОКАЛЬНО И БЕРЕЖНО", "Твои данные — у тебя", "Вход хранится в Keychain, а рассылка работает прямо на твоём iPhone."),
        ("sparkles", "ГОТОВО", "Держим огонь вместе", "Подключи TikTok и запусти первое продление, когда будешь готов.")
    ]

    var body: some View {
        ZStack {
            UiTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("УГОЛЁК").font(.caption.weight(.bold)).tracking(2).foregroundStyle(UiTheme.textMuted)
                    Spacer()
                    if step < pages.count - 1 { Button("Пропустить") { finish() }.font(.subheadline.weight(.semibold)).foregroundStyle(UiTheme.textMuted).accessibilityHint("Завершить онбординг") }
                }
                .padding(.horizontal, 24).padding(.top, 16)

                Spacer()
                pageContent
                Spacer()

                HStack(spacing: 7) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule().fill(index == step ? UiTheme.accent : Color.white.opacity(0.18)).frame(width: index == step ? 24 : 7, height: 7)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
                .padding(.bottom, 20)
                UgolekButton(step == pages.count - 1 ? "Начать" : "Дальше", systemImage: step == pages.count - 1 ? "arrow.right" : "chevron.right", prominent: true) { advance() }
                    .accessibilityHint(step == pages.count - 1 ? "Начать использование приложения" : "Перейти к следующему шагу")
                    .padding(.horizontal, 24).padding(.bottom, 16)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.65)) { appeared = true }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var pageContent: some View {
        let page = pages[step]
        return VStack(spacing: 25) {
            ZStack {
                Circle().fill(UiTheme.accent.opacity(0.10)).frame(width: 184, height: 184)
                Circle().stroke(UiTheme.accent.opacity(0.25), lineWidth: 1).frame(width: 184, height: 184)
                Image(systemName: page.icon).font(.system(size: 62, weight: .medium)).foregroundStyle(UiTheme.accent)
                    .symbolEffect(.bounce, value: step)
            }
            VStack(spacing: 10) {
                Text(page.eyebrow).font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(UiTheme.accent)
                Text(page.title).font(.system(size: 34, weight: .bold, design: .rounded)).kerning(-1).multilineTextAlignment(.center).foregroundStyle(UiTheme.text)
                Text(page.text).font(.system(size: 17, design: .rounded)).foregroundStyle(UiTheme.textMuted).multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 28)
            }
        }
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 12)
        .id(step)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity.combined(with: .move(edge: .leading))))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.38), value: step)
    }

    private func advance() {
        if step < pages.count - 1 {
            if reduceMotion { step += 1 } else { withAnimation { step += 1 } }
        } else { finish() }
    }

    private func finish() {
        if reduceMotion { isComplete = true } else { withAnimation(.easeInOut(duration: 0.4)) { isComplete = true } }
    }
}

#Preview("First Step") {
    OnboardingPreviewWrapper(startComplete: false)
}

#Preview("All Done") {
    OnboardingPreviewWrapper(startComplete: true)
}

private struct OnboardingPreviewWrapper: View {
    @State var isComplete: Bool
    init(startComplete: Bool) { _isComplete = State(initialValue: startComplete) }
    var body: some View { OnboardingView(isComplete: $isComplete) }
}
