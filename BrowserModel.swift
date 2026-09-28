import Foundation
import WebKit
import UIKit

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var tabs: [BrowserTab]
    @Published var selectedTabID: UUID
    @Published var address: String
    @Published var pageTitle: String = "Clean Browser Pro"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var shieldStatus = "Privacy Shield voorbereiden…"
    @Published var lastError: String?

    let settings = AppSettings.shared
    let bookmarks = BookmarkStore.shared

    var selectedTab: BrowserTab {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0]
    }

    var webView: WKWebView { selectedTab.webView }

    override init() {
        let firstWebView = Self.makeWebView(settings: AppSettings.shared)
        let firstTab = BrowserTab(webView: firstWebView)
        self.tabs = [firstTab]
        self.selectedTabID = firstTab.id
        self.address = AppSettings.shared.homePage
        super.init()

        configure(firstWebView)
        Task {
            await applyPrivacyShield(to: firstWebView)
            loadHome()
        }
    }

    private static func makeWebView(settings: AppSettings) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = settings.javaScriptEnabled
        configuration.defaultWebpagePreferences = pagePreferences

        let controller = WKUserContentController()
        let privacyScript = WKUserScript(
            source: """
            (() => {
              try { Object.defineProperty(navigator, 'doNotTrack', { get: () => '1' }); } catch (_) {}
              try {
                if (navigator.sendBeacon) {
                  navigator.sendBeacon = function(){ return false; };
                }
              } catch (_) {}
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(privacyScript)
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = false
        view.scrollView.keyboardDismissMode = .interactive

        if settings.desktopMode {
            view.customUserAgent =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        }

        return view
    }

    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
    }

    private func applyPrivacyShield(to view: WKWebView) async {
        do {
            try await ContentBlockerService.install(
                on: view.configuration.userContentController,
                strict: settings.strictBlocking
            )
            shieldStatus = settings.strictBlocking ? "Privacy Shield: streng" : "Privacy Shield: aan"
        } catch {
            shieldStatus = "Privacy Shield: fout"
            lastError = error.localizedDescription
        }
    }

    func rebuildForPrivacySettings() {
        resetPrivateSession(reason: "Privacy-instelling gewijzigd")
    }

    func loadHome() {
        load(settings.homePage)
    }

    func load(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let target: URL?
        if let direct = URL(string: input),
           let scheme = direct.scheme?.lowercased(),
           ["https", "http"].contains(scheme) {
            target = normalizedURL(direct)
        } else if input.contains("."),
                  !input.contains(" "),
                  let direct = URL(string: "https://" + input) {
            target = direct
        } else {
            target = settings.searchEngine.searchURL(for: input)
        }

        guard let target else { return }

        if settings.httpsOnly && target.scheme?.lowercased() != "https" {
            lastError = "HTTPS-only is ingeschakeld. Deze niet-versleutelde HTTP-pagina is geblokkeerd."
            return
        }

        var request = URLRequest(url: target)
        request.setValue("1", forHTTPHeaderField: "DNT")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        address = target.absoluteString
        webView.load(request)
    }

    private func normalizedURL(_ url: URL) -> URL {
        guard settings.httpsOnly,
              url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        return components.url ?? url
    }

    func newTab(loadHomePage: Bool = true) {
        let view = Self.makeWebView(settings: settings)
        configure(view)
        let tab = BrowserTab(webView: view)
        tabs.append(tab)
        selectedTabID = tab.id
        syncFromSelectedTab()

        Task {
            await applyPrivacyShield(to: view)
            if loadHomePage { loadHome() }
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        syncFromSelectedTab()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        purge(view: removed.webView)

        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
            syncFromSelectedTab()
        } else {
            objectWillChange.send()
        }
    }

    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reloadFromOrigin() }
    func stop() { webView.stopLoading() }

    func addCurrentBookmark() {
        let url = webView.url?.absoluteString ?? address
        bookmarks.add(title: pageTitle, url: url)
    }

    func clearNow() {
        resetPrivateSession(reason: "Handmatig gewist")
    }

    func resetPrivateSession(reason: String) {
        guard settings.clearOnBackground || reason != "App naar achtergrond" else { return }

        for tab in tabs { purge(view: tab.webView) }

        let replacement = Self.makeWebView(settings: settings)
        configure(replacement)
        let tab = BrowserTab(webView: replacement)
        tabs = [tab]
        selectedTabID = tab.id

        address = settings.homePage
        pageTitle = "Clean Browser Pro"
        canGoBack = false
        canGoForward = false
        isLoading = false
        shieldStatus = "Privacy Shield voorbereiden…"

        Task {
            await applyPrivacyShield(to: replacement)
            loadHome()
        }
    }

    private func purge(view: WKWebView) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        let store = view.configuration.websiteDataStore
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { }
    }

    func capturePageSegments() async throws -> [PageSegment] {
        let script = """
        (() => {
          const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','TEXTAREA','INPUT','SELECT','OPTION','CODE','PRE']);
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          const nodes = [];
          const payload = [];
          let n;
          while ((n = walker.nextNode())) {
            if (!n.parentElement || skip.has(n.parentElement.tagName)) continue;
            const style = getComputedStyle(n.parentElement);
            if (style.display === 'none' || style.visibility === 'hidden') continue;
            const t = n.nodeValue.trim();
            if (t.length < 2 || t.length > 800) continue;
            const id = nodes.length;
            nodes.push(n);
            payload.push({id:id, text:t});
            if (nodes.length >= 300) break;
          }
          window.__cleanBrowserTranslationNodes = nodes;
          return JSON.stringify(payload);
        })();
        """
        let value = try await webView.evaluateJavaScript(script)
        guard let json = value as? String,
              let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([PageSegment].self, from: data)
    }

    func applyTranslations(_ translations: [Int: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: translations, options: [])
        guard let json = String(data: data, encoding: .utf8) else { return }

        let script = """
        (() => {
          const map = \(json);
          const nodes = window.__cleanBrowserTranslationNodes || [];
          Object.keys(map).forEach(k => {
            const i = Number(k);
            if (nodes[i]) nodes[i].nodeValue = map[k];
          });
          document.documentElement.setAttribute('data-cleanbrowser-translated','1');
          return true;
        })();
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    private func applyTextScale(to view: WKWebView) {
        let percent = Int(max(0.75, min(settings.textScale, 1.5)) * 100)
        view.evaluateJavaScript(
            "document.documentElement.style.webkitTextSizeAdjust='\(percent)%';"
        ) { _, _ in }
    }

    private func syncFromSelectedTab() {
        address = webView.url?.absoluteString ?? selectedTab.urlString
        pageTitle = webView.title ?? selectedTab.title
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        objectWillChange.send()
    }

    private func updateState(for view: WKWebView) {
        guard let tab = tabs.first(where: { $0.webView === view }) else { return }
        tab.urlString = view.url?.absoluteString ?? tab.urlString
        tab.title = view.title ?? tab.title

        if tab.id == selectedTabID {
            address = tab.urlString
            pageTitle = tab.title
            canGoBack = view.canGoBack
            canGoForward = view.canGoForward
            isLoading = view.isLoading
        }
        objectWillChange.send()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateState(for: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState(for: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyTextScale(to: webView)
        updateState(for: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            lastError = error.localizedDescription
        }
        updateState(for: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            lastError = error.localizedDescription
        }
        updateState(for: webView)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about"].contains(scheme) else {
            decisionHandler(.cancel)
            return
        }

        if settings.httpsOnly && scheme == "http" {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                if let secure = components.url {
                    var req = navigationAction.request
                    req.url = secure
                    webView.load(req)
                }
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }

        if settings.blockPopups && navigationAction.navigationType != .linkActivated {
            return nil
        }

        load(url.absoluteString)
        return nil
    }
}
