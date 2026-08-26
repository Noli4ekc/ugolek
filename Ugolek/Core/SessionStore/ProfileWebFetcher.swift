import WebKit

/// Часть B/C фолбэк: лёгкий offscreen WKWebView грузит публичный профиль
/// настоящим браузерным движком — TikTok отдаёт ему полную страницу с данными
/// (прямому URLSession он отдаёт заглушку ~1.5 КБ без данных).
@MainActor
final class ProfileWebFetcher: NSObject, WKNavigationDelegate {
    static let shared = ProfileWebFetcher()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var handle = ""

    /// Ник профиля или nil (не удалось за таймаут / бот-заглушка и в браузере).
    func fetchNickname(handle: String) async -> String? {
        guard continuation == nil else { return nil }   // один запрос за раз
        let clean = handle.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }
        guard clean == handle, !clean.isEmpty,
              let url = URL(string: "https://www.tiktok.com/@\(clean)") else { return nil }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        webView.navigationDelegate = self
        webView.customUserAgent = SessionStore.desktopUserAgent
        self.webView = webView
        self.handle = clean.lowercased()

        return await withCheckedContinuation { cont in
            continuation = cont
            webView.load(URLRequest(url: url))
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ nickname: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        cont.resume(returning: nickname)
        webView?.stopLoading()
        webView = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            // контент гидрируется асинхронно — опрашиваем до 6 секунд
            for _ in 0..<6 {
                if let nick = await self.extractNickname() {
                    self.finish(nick)
                    return
                }
                if self.continuation == nil { return }
                try? await Task.sleep(for: .seconds(1))
            }
            self.finish(nil)
        }
    }

    private func extractNickname() async -> String? {
        guard let webView else { return nil }
        let js = """
        (function(){
          const H = '\(handle)';
          const out = (found, nickname, via) => JSON.stringify({found, nickname: nickname || null, via});
          const el = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
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
              if (hit) return out(true, hit, 'uniData');
            } catch (e) {}
          }
          const meta = document.querySelector('meta[property="og:title"]')
            || document.querySelector('meta[name="description"]');
          const metaText = (meta && meta.content) || '';
          const byAt = metaText.match(/^(.*?)\\s*\\(@/);
          if (byAt && byAt[1]) return out(true, byAt[1], 'og-title');
          const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let tn;
          while ((tn = tw.nextNode())) {
            const m = (tn.textContent || '').trim().match(/^@([A-Za-z0-9._]{2,30})$/);
            if (m && m[1].toLowerCase() === H) {
              const h1 = document.querySelector('h1');
              return out(true, h1 ? (h1.innerText || '').trim() : null, 'at-text');
            }
          }
          return out(false, null, 'нет данных на странице');
        })()
        """
        guard let raw = try? await webView.evaluateJavaScript(js) as? String,
              let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              obj["found"] as? Bool == true else { return nil }
        return obj["nickname"] as? String
    }
}
