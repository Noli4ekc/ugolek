import SwiftUI

/// Shared visual language for Ugolek: Opal-inspired restraint with a warm fire accent.
enum UiTheme {
    static let background = Color.black
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let surfaceRaised = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let button = Color(red: 0.184, green: 0.184, blue: 0.184)
    static let text = Color.white
    static let textMuted = Color.white.opacity(0.58)
    static let textFaint = Color.white.opacity(0.32)
    static let accent = Color(red: 0.98, green: 0.57, blue: 0.24)
    static let success = Color(red: 0.20, green: 0.83, blue: 0.60)

    static let screenPadding: CGFloat = 24
    static let rowRadius: CGFloat = 14
}

struct ScreenTitle: View {
    let text: String
    var subtitle: String?

    init(_ text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    init(text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .kerning(-1)
                .foregroundStyle(UiTheme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(UiTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UiTheme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
}

struct UgolekCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(UiTheme.surface, in: RoundedRectangle(cornerRadius: UiTheme.rowRadius, style: .continuous))
    }
}

struct UgolekButton: View {
    let title: String
    let systemImage: String?
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.action = action
    }

    init(title: String, systemImage: String? = nil, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(prominent ? Color.black : UiTheme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(prominent ? UiTheme.accent : UiTheme.button, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String
    let color: Color
    let title: String
    let accessory: Accessory

    init(icon: String, color: Color, title: String, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon; self.color = color; self.title = title; self.accessory = accessory()
    }

    init(icon: String, iconColor: Color, title: String, value: String) where Accessory == Text {
        self.icon = icon; self.color = iconColor; self.title = title
        self.accessory = Text(value)
            .font(.system(size: 14))
            .foregroundStyle(UiTheme.textMuted)
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(UiTheme.text)
            Spacer(minLength: 8)
            accessory
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Card Style Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(UiTheme.surface, in: RoundedRectangle(cornerRadius: UiTheme.rowRadius, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
