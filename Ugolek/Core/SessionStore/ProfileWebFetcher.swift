import WebKit

/// Часть B/C фолбэк: лёгкий offscreen WKWebView грузит публичный профиль
/// настоящим Safari-движком. У свежего WebView нет кук — TikTok может отдать
/// челлендж, поэтому бюджет 25 с (цепочка «заглушка → JS → редирект → страница»)
/// и подробный diag: если и здесь пусто, дальше идёт полный движок (InboxRunner).
@MainActor
final class ProfileWebFetcher: NSObject, WKNavigationDelegate {
    static let shared = ProfileWebFetcher()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<(nickname: String?, diag: String), Never>?
    private var timeoutTask: Task<Void, Never>?
    private var handle = ""
    private var lastExtractDiag = ""

    /// (ник, diag) — ник nil означает «не удалось», diag объясняет чем.
    func fetchNickname(handle: String) async -> (nickname: String?, diag: String) {
        guard continuation == nil else { return (nil, "webview: уже занят") }
        let clean = handle.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
        guard clean == handle, !clean.isEmpty,
              let url = URL(string: "https://www.tiktok.com/@\(clean)") else {
            return (nil, "webview: bad-handle")
        }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        webView.navigationDelegate = self
        webView.customUserAgent = SessionStore.desktopUserAgent
        self.webView = webView
        self.handle = clean.lowercased()
        lastExtractDiag = ""

        let result: (nickname: String?, diag: String) = await withCheckedContinuation { cont in
            continuation = cont
            webView.load(URLRequest(url: url))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                self?.finish(nickname: nil, timeoutDiag: "таймаут 25 с")
            }
        }
        webView.stopLoading()
        self.webView = nil
        return result
    }

    private func finish(nickname: String?, timeoutDiag: String = "") {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if let nickname {
            cont.resume(returning: (nickname, ""))
        } else {
            let diag = timeoutDiag.isEmpty ? (lastExtractDiag.isEmpty ? "нет данных" : lastExtractDiag) : timeoutDiag
            cont.resume(returning: (nil, "webview: " + diag))
        }
        webView?.stopLoading()
        webView = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            // гидрация асинхронная — опрашиваем, пока не сработает таймаут
            while self.continuation != nil {
                if let nick = await self.extractNickname() {
                    self.finish(nickname: nick)
                    return
                }
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    private func extractNickname() async -> String? {
        guard let webView else { return nil }
        let js = """
        (function(){
          const H = '\(handle)';
          const steps = [];
          const el = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
          steps.push('uniData:' + (el ? 'да' : 'нет'));
          if (el) {
            try {
              const data = JSON.parse(el.textContent);
              let hit = null;
              const walk = (n) => {
                if (hit || !n || typeof n !== 'object') return;
                if (Array.isArray(n)) { n.forEach(walk); return; }
                if (String(n.uniqueId || '').toLowerCase() === H) { hit = n.nickname || null; return; }
                Object.values(n).forEach(walk);
              };
              walk(data);
              if (hit) return JSON.stringify({ found: true, nickname: hit, diag: 'uniData' });
            } catch (e) { steps.push('parseErr'); }
          }
          const meta = document.querySelector('meta[property="og:title"]')
            || document.querySelector('meta[name="description"]');
          const metaText = (meta && meta.content) || '';
          steps.push('og:"' + metaText.slice(0, 40) + '"');
          const byAt = metaText.match(/^(.*?)\\s*\\(@/);
          if (byAt && byAt[1]) return JSON.stringify({ found: true, nickname: byAt[1], diag: 'og' });
          const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let tn;
          while ((tn = tw.nextNode())) {
            const m = (tn.textContent || '').trim().match(/^@([A-Za-z0-9._]{2,30})$/);
            if (m && m[1].toLowerCase() === H) {
              const h1 = document.querySelector('h1');
              return JSON.stringify({ found: true, nickname: h1 ? (h1.innerText || '').trim() : null, diag: 'at-text' });
            }
          }
          steps.push('url:' + location.pathname);
          return JSON.stringify({ found: false, diag: steps.join(' ') });
        })()
        """
        guard let raw = try? await webView.evaluateJavaScript(js) as? String,
              let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            lastExtractDiag = "js-ошибка"
            return nil
        }
        lastExtractDiag = (obj["diag"] as? String) ?? ""
        if obj["found"] as? Bool == true {
            return obj["nickname"] as? String
        }
        return nil
    }
}
