import UIKit
import WebKit

enum InboxError: LocalizedError {
    case noWindowScene
    case loginRequired
    case loadTimeout
    case scriptMissing

    var errorDescription: String? {
        switch self {
        case .noWindowScene: return "Нет активной сцены окна"
        case .loginRequired: return "Сессия TikTok истекла — нужен повторный вход"
        case .loadTimeout: return "Страница сообщений TikTok не загрузилась"
        case .scriptMissing: return "Файл автоматизации не найден в сборке"
        }
    }
}

@MainActor
final class InboxRunner: NSObject {
    static let shared = InboxRunner()

    struct BridgeMessage: Codable {
        let type: String
        var username: String? = nil
        var ok: Bool? = nil
        var error: String? = nil
        var detail: String? = nil
        var text: String? = nil
    }

    private var window: UIWindow?
    private var webView: WKWebView?
    private var loadedURL: URL?
    private var loadContinuation: CheckedContinuation<URL, Error>?
    private var resultContinuation: CheckedContinuation<BridgeMessage, Never>?
    private var runToken = 0
    private var script = ""

    var onLog: ((String) -> Void)?

    func ensureLoaded() async throws {
        if webView != nil, loadedURL != nil { return }

        try await makeWindowAndWebView()

        let url: URL = try await withCheckedThrowingContinuation { cont in
            loadContinuation = cont
            let request = URLRequest(url: URL(string: "https://www.tiktok.com/messages?lang=en")!)
            webView?.load(request)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(40))
                guard let self, let pending = self.loadContinuation else { return }
                self.loadContinuation = nil
                pending.resume(throwing: InboxError.loadTimeout)
            }
        }

        if url.path.contains("/login") { throw InboxError.loginRequired }

        try await Task.sleep(for: .seconds(2))
        if let result = try? await webView?.evaluateJavaScript(
            "document.querySelector('[data-e2e=top-login-button]') !== null"
        ), let loggedOut = result as? Bool, loggedOut {
            SessionStore.shared.invalidate()
            throw InboxError.loginRequired
        }

        try injectScript()
        try await Task.sleep(for: .seconds(3))
        loadedURL = url
    }

    func send(
        to handle: String,
        message: String,
        isGroup: Bool,
        dryRun: Bool,
        fast: Bool = false
    ) async -> BridgeMessage {
        guard webView != nil else {
            return BridgeMessage(type: "result", username: handle, ok: false, error: "Движок не загружен")
        }

        let payload: [String: Any] = [
            "username": handle,
            "message": message,
            "isGroup": isGroup,
            "dryRun": dryRun,
            "fast": fast,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return BridgeMessage(type: "result", username: handle, ok: false, error: "Не удалось собрать команду")
        }

        let first = await runJS(json, handle: handle)
        guard first.ok == false, let error = first.error, error.contains("Чат не открылся") else { return first }

        // правая панель не переключилась — пробуем после полной перезагрузки страницы
        await reloadPage()
        let second = await runJS(json, handle: handle)
        guard second.ok == false, let error2 = second.error, error2.contains("Чат не открылся") else { return second }

        // перезагрузка не помогла — чистим сайтовые данные TikTok (кроме куки): вдруг битое DM-состояние
        await SessionStore.shared.clearSiteData(keepingCookies: true)
        await reloadPage()
        return await runJS(json, handle: handle)
    }

    private func runJS(_ json: String, handle: String) async -> BridgeMessage {
        runToken += 1
        let token = runToken
        return await withCheckedContinuation { cont in
            resultContinuation = cont
            webView?.evaluateJavaScript("Ugolek.run(\(json))", completionHandler: nil)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(95))
                guard let self, self.runToken == token, let pending = self.resultContinuation else { return }
                self.resultContinuation = nil
                pending.resume(returning: BridgeMessage(
                    type: "result",
                    username: handle,
                    ok: false,
                    error: "Превышено время ожидания (95 с)"
                ))
            }
        }
    }

    private func reloadPage() async {
        guard let webView else { return }
        webView.load(URLRequest(url: URL(string: "https://www.tiktok.com/messages?lang=en")!))
        try? await Task.sleep(for: .seconds(8))
        try? injectScript()
        try? await Task.sleep(for: .seconds(3))
    }

    func discovery() async -> String {
        guard let webView else { return "Движок ещё не загружался" }
        let js = "JSON.stringify(Ugolek.discovery())"
        if let result = try? await webView.evaluateJavaScript(js),
           let text = result as? String {
            return text
        }
        return "Диагностика не выполнена"
    }

    func chatProbe() async -> String {
        guard let webView else { return "Движок ещё не загружался" }
        _ = try? await webView.evaluateJavaScript("Ugolek.openFirstChat()")
        try? await Task.sleep(for: .seconds(30))
        if let result = try? await webView.evaluateJavaScript("JSON.stringify(Ugolek.chatSnapshot())"),
           let text = result as? String {
            return text
        }
        return "Снимок чата не выполнен"
    }

    func teardown() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        window?.isHidden = true
        window = nil
        loadedURL = nil
    }

    private func makeWindowAndWebView() async throws {
        guard webView == nil else { return }

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { throw InboxError.noWindowScene }

        let size = CGSize(width: 1920, height: 1080)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -size.width - 10, y: 0, width: size.width, height: size.height)
        window.alpha = 0.01
        window.backgroundColor = .clear
        window.isHidden = false

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let contentController = WKUserContentController()
        contentController.add(self, name: "ugolekBridge")
        configuration.userContentController = contentController

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        webView.customUserAgent = SessionStore.desktopUserAgent
        webView.navigationDelegate = self
        window.addSubview(webView)
        window.layoutIfNeeded()

        self.window = window
        self.webView = webView

        await SessionStore.shared.restoreCookies(into: configuration.websiteDataStore.httpCookieStore)
    }

    private func injectScript() throws {
        guard let url = Bundle.main.url(forResource: "send", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw InboxError.scriptMissing
        }
        script = source
        webView?.evaluateJavaScript(source, completionHandler: nil)
    }

    private func handle(_ message: BridgeMessage) {
        switch message.type {
        case "log":
            if let text = message.text { onLog?(text) }
        case "result":
            if let pending = resultContinuation {
                resultContinuation = nil
                pending.resume(returning: message)
            }
        default:
            break
        }
    }
}

extension InboxRunner: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "ugolekBridge" else { return }
        Task { @MainActor in
            let body = message.body
            let data: Data
            if let text = body as? String {
                data = Data(text.utf8)
            } else if JSONSerialization.isValidJSONObject(body),
                      let encoded = try? JSONSerialization.data(withJSONObject: body) {
                data = encoded
            } else {
                return
            }
            if let decoded = try? JSONDecoder().decode(BridgeMessage.self, from: data) {
                self.handle(decoded)
            }
        }
    }
}

extension InboxRunner: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let pending = self.loadContinuation else { return }
            self.loadContinuation = nil
            pending.resume(returning: webView.url ?? URL(string: "https://www.tiktok.com")!)
        }
    }
}
