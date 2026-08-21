import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = SessionStore.shared

    var body: some View {
        NavigationStack {
            TikTokLoginWebView(
                onSuccess: {
                    session.refresh()
                    dismiss()
                }
            )
            .navigationTitle("Вход в TikTok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

struct TikTokLoginWebView: UIViewRepresentable {
    let onSuccess: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SessionStore.shared.savedUserAgent
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://www.tiktok.com/login?lang=ru") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSuccess: onSuccess) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSuccess: () -> Void
        private var handled = false

        init(onSuccess: @escaping () -> Void) {
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !handled else { return }
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                guard let sid = cookies.first(where: { $0.name == "sessionid" }),
                      !sid.value.isEmpty else { return }
                self.handled = true
                SessionStore.shared.save(sessionID: sid.value, userAgent: webView.customUserAgent)
                DispatchQueue.main.async { self.onSuccess() }
            }
        }
    }
}
