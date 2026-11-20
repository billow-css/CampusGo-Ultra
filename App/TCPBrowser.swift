import SwiftUI
import WebKit

@MainActor
struct TCPModule: CampusModule {
    let browser: TCPBrowser
    let descriptor = ModuleDescriptor(id: "campus.tcp", name: "TCP",
        description: "在 CampusGo 内搜索、打开网页和查看文档。", icon: "globe",
        surfaces: [.detail, .settings, .navigation])
    var defaultNavigationVisible: Bool { false }
    func setEnabled(_ enabled: Bool) { if !enabled { browser.closePage() } }
    func detail(context: ModuleContext) -> AnyView? {
        AnyView(TCPPage().environmentObject(browser))
    }
    func settings(context: ModuleContext) -> AnyView? {
        AnyView(TCPSettings(navigationVisible: context.navigationVisible).environmentObject(browser))
    }
}

@MainActor
final class TCPBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var currentURL: URL?
    @Published private(set) var progress: Double = 0
    @Published private(set) var loading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var error: String?
    @Published private(set) var externalURL: URL?
    @Published private(set) var clearingData = false
    @Published private(set) var hasPage = false
    @Published var styleEnabled: Bool {
        didSet {
            defaults.set(styleEnabled, forKey: "campus.tcp.style")
            if let page {
                configureThemeScript(for: page.configuration.userContentController)
                applyStyle(to: page)
            }
        }
    }

    private let defaults: UserDefaults
    private let profile = UUID(uuidString: "70735E78-EBD0-4409-BCBB-12FF7E6FFACB")!
    private var page: WKWebView?
    private var pendingURL: URL?
    private var observations: [NSKeyValueObservation] = []
    private var navigation: WKNavigation?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        styleEnabled = defaults.object(forKey: "campus.tcp.style") as? Bool ?? true
        super.init()
    }

    private var dataStore: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: profile) }

    func webView() -> WKWebView {
        if let page { return page }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        configureThemeScript(for: config.userContentController)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        page = web
        observations = [
            observe(web, \.url), observe(web, \.estimatedProgress), observe(web, \.isLoading),
            observe(web, \.canGoBack), observe(web, \.canGoForward)
        ]
        return web
    }

    private func observe<Value>(_ web: WKWebView, _ path: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        web.observe(path, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, view === self.page else { return }
                if let url = view.url, Self.isWeb(url) { self.currentURL = url }
                self.progress = view.estimatedProgress
                self.loading = view.isLoading
                self.canGoBack = view.canGoBack
                self.canGoForward = view.canGoForward
            }
        }
    }

    func submit(_ input: String) {
        guard !clearingData else { return }
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if query.contains("://") {
            guard let url = URL(string: query), Self.isWeb(url) else {
                error = "请输入有效的 HTTPS 地址。"
                return
            }
            open(url)
        } else if !query.contains(where: \.isWhitespace), let candidate = URL(string: "https://" + query),
                  candidate.host?.contains(".") == true, Self.isWeb(candidate) {
            open(candidate)
        } else {
            var search = URLComponents(string: "https://duckduckgo.com/")!
            search.queryItems = [URLQueryItem(name: "q", value: query)]
            if let url = search.url { open(url) }
        }
    }

    func open(_ url: URL) {
        guard !clearingData, Self.isWeb(url) else { return }
        error = nil; externalURL = nil
        pendingURL = url
        hasPage = true
        navigation = webView().load(URLRequest(url: url))
    }

    func back() {
        error = nil; externalURL = nil
        navigation = page?.goBack()
    }
    func forward() {
        error = nil; externalURL = nil
        navigation = page?.goForward()
    }
    func reload() {
        if error != nil, let pendingURL { open(pendingURL) }
        else { navigation = page?.reload() }
    }
    func stop() { page?.stopLoading() }

    func closePage() {
        observations.removeAll()
        page?.stopLoading()
        page?.navigationDelegate = nil
        page?.uiDelegate = nil
        page = nil; navigation = nil
        currentURL = nil; pendingURL = nil; externalURL = nil; error = nil
        canGoBack = false; canGoForward = false; loading = false; progress = 0
        hasPage = false
    }

    func clearData() async {
        guard !clearingData else { return }
        clearingData = true
        closePage()
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        clearingData = false
    }

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        if url.host?.lowercased() == "accounts.google.com" {
            offerExternalLogin(for: url)
            decisionHandler(.cancel)
            return
        }
        guard Self.isWeb(url) else {
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            error = "TCP 支持 HTTPS 网页。其他类型的链接请使用系统浏览器。"
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame?.isMainFrame == true {
            pendingURL = url
            error = nil; externalURL = nil
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url else { return nil }
        if url.host?.lowercased() == "accounts.google.com" { offerExternalLogin(for: url) }
        else if action.navigationType == .linkActivated, Self.isWeb(url) {
            error = nil; externalURL = nil
            pendingURL = url
            navigation = webView.load(action.request)
        }
        return nil
    }

    private func offerExternalLogin(for url: URL) {
        externalURL = currentURL ?? pendingURL ?? url
        error = "此登录流程需要系统浏览器。浏览器与 TCP 的登录状态各自保存。"
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.navigation = navigation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyStyle(to: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) {
        report(failure, navigation: navigation)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) {
        report(failure, navigation: navigation)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "网页进程已结束，请重新加载。"
    }
    private func report(_ failure: Error, navigation failedNavigation: WKNavigation?) {
        let failure = failure as NSError
        guard failedNavigation === navigation || navigation == nil,
              !(failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled),
              failure.domain != "WebKitErrorDomain" || failure.code != 102 else { return }
        error = failure.localizedDescription
    }

    private func configureThemeScript(for controller: WKUserContentController) {
        controller.removeAllUserScripts()
        guard styleEnabled else { return }
        controller.addUserScript(WKUserScript(source: themeScript, injectionTime: .atDocumentEnd,
                                             forMainFrameOnly: true, in: .defaultClient))
    }

    private func applyStyle(to web: WKWebView) {
        web.evaluateJavaScript(themeScript, in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// The built-in stylesheet runs on the top-level page and preserves site layout and contrast.
    private static let baseCSS = """
    :root { --campus-tcp-accent: #1680a3; }
    @media (prefers-color-scheme: dark) {
        :root { --campus-tcp-accent: #68bdd8; }
    }
    body { font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif; }
    h1, h2, h3 { letter-spacing: -.018em !important; }
    a[href] {
        text-underline-offset: .2em !important;
        text-decoration-color: var(--campus-tcp-accent) !important;
    }
    a[href]:hover { text-decoration-line: underline !important; }
    :is(a, button, input, select, textarea, summary):focus-visible {
        outline: 2px solid var(--campus-tcp-accent) !important;
        outline-offset: 2px !important;
    }
    :is(input, select, textarea, progress, meter) { accent-color: var(--campus-tcp-accent) !important; }
    :is(input:not([type]), input[type="text"], input[type="search"], textarea, select, pre) {
        border-radius: 8px !important;
    }
    ::selection { background-color: #2d83aa66; }
    """

    private static let githubDocsCSS = """
    main pre { border-radius: 12px !important; }
    main :is(article, #article-contents) :is(p, li) { line-height: 1.65; }
    """

    private var themeScript: String {
        let enabled = styleEnabled ? "true" : "false"
        return """
        (() => {
          const id = 'campus-tcp-theme';
          const existing = document.getElementById(id);
          if (!\(enabled)) {
            existing?.remove();
            return;
          }
          if (existing || location.protocol !== 'https:' || !document.head) return;
          const style = document.createElement('style');
          style.id = id;
          style.textContent = `\(Self.baseCSS)`;
          if (location.hostname === 'docs.github.com') {
            style.textContent += `\(Self.githubDocsCSS)`;
          }
          document.head.appendChild(style);
        })();
        """
    }

}

private struct TCPWebSurface: NSViewRepresentable {
    let browser: TCPBrowser

    func makeNSView(context: Context) -> Container { Container(page: browser.webView()) }
    func updateNSView(_ view: Container, context: Context) {}
    static func dismantleNSView(_ view: Container, coordinator: ()) { view.detach() }

    /// Only the active CampusGo window can host the shared TCP page.
    final class Container: NSView {
        private let page: WKWebView

        init(page: WKWebView) {
            self.page = page
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            guard let window else { detach(); return }
            NotificationCenter.default.addObserver(self, selector: #selector(attach),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            if window.isKeyWindow || page.superview == nil { attach() }
        }

        @objc private func attach() {
            guard page.superview !== self else { return }
            page.removeFromSuperview()
            page.frame = bounds
            page.autoresizingMask = [.width, .height]
            addSubview(page)
        }

        func detach() {
            if page.superview === self { page.removeFromSuperview() }
        }
    }
}

private struct TCPPage: View {
    @EnvironmentObject private var browser: TCPBrowser
    @Environment(\.nuistAccent) private var accent
    @State private var address = ""
    @FocusState private var editingAddress: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if browser.loading { ProgressView(value: browser.progress).progressViewStyle(.linear) }
            if let error = browser.error {
                HStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    if let url = browser.externalURL {
                        Button("在系统浏览器打开") { NSWorkspace.shared.open(url) }
                    }
                }.font(.caption).padding(12).background(CampusTheme.board)
            }
            Divider()
            if browser.hasPage {
                TCPWebSurface(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                startPage
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { address = browser.currentURL?.absoluteString ?? "" }
        .onChange(of: browser.currentURL) { _, url in if !editingAddress { address = url?.absoluteString ?? "" } }
        .onChange(of: editingAddress) { wasEditing, isEditing in
            if wasEditing && !isEditing, let url = browser.currentURL { address = url.absoluteString }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: browser.back) { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack).help("后退").accessibilityLabel("后退")
            Button(action: browser.forward) { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward).help("前进").accessibilityLabel("前进")
            Button {
                if browser.loading { browser.stop() } else { browser.reload() }
            } label: {
                Image(systemName: browser.loading ? "xmark" : "arrow.clockwise")
            }.disabled(!browser.hasPage).help(browser.loading ? "停止加载" : "刷新")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入网址或搜索", text: $address)
                    .textFieldStyle(.plain).focused($editingAddress)
                    .onSubmit {
                        let input = address
                        editingAddress = false
                        browser.submit(input)
                    }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .trailing) {
                Button { editingAddress = true } label: { EmptyView() }
                    .keyboardShortcut("l", modifiers: .command).frame(width: 0, height: 0).accessibilityHidden(true)
            }
            Button { browser.styleEnabled.toggle() } label: {
                Image(systemName: browser.styleEnabled ? "paintbrush.pointed.fill" : "paintbrush.pointed")
                    .foregroundStyle(browser.styleEnabled ? accent : Color.secondary)
            }
            .help(browser.styleEnabled ? "关闭 TCP 网页主题" : "启用 TCP 网页主题")
            .accessibilityLabel(browser.styleEnabled ? "关闭 TCP 网页主题" : "启用 TCP 网页主题")
            Button(action: browser.closePage) { Image(systemName: "house") }.help("回到起始页")
            Button {
                if let url = browser.currentURL { NSWorkspace.shared.open(url) }
            } label: { Image(systemName: "arrow.up.right.square") }
                .disabled(browser.currentURL == nil).help("在系统浏览器打开").accessibilityLabel("在系统浏览器打开")
        }.buttonStyle(.bordered).controlSize(.small).padding(12)
    }

    private var startPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "globe").font(.system(size: 40, weight: .light)).foregroundStyle(accent)
            Text("TCP").font(.largeTitle.weight(.semibold))
            Text("输入网址或关键词，也可以直接打开常用站点。").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                shortcut("GitHub 文档", "https://docs.github.com/")
                shortcut("ChatGPT", "https://chatgpt.com/")
                shortcut("Claude", "https://claude.ai/")
                shortcut("DeepSeek", "https://chat.deepseek.com/")
            }.disabled(browser.clearingData)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcut(_ name: String, _ address: String) -> some View {
        Button(name) { if let url = URL(string: address) { browser.open(url) } }.buttonStyle(.bordered)
    }
}

private struct TCPSettings: View {
    @EnvironmentObject private var browser: TCPBrowser
    @State private var confirmsClear = false
    var navigationVisible: Binding<Bool>?

    var body: some View {
        Form {
            if let navigationVisible { Toggle("在顶部显示 TCP 标签页", isOn: navigationVisible) }
            Section("网站主题") {
                Toggle("在网页上应用 TCP 样式", isOn: $browser.styleEnabled)
                Text("TCP 向网页注入自有 CSS，调整文字、链接、输入框和代码块。可在浏览工具栏中即时切换。").font(.caption).foregroundStyle(.secondary)
            }
            Section("网站数据") {
                Text("TCP 使用自己的会话存储。你可以清除 Cookie、缓存和网站登录状态。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("清除 TCP 网站数据…", role: .destructive) { confirmsClear = true }
                    .disabled(browser.clearingData)
            }
        }.formStyle(.grouped)
            .confirmationDialog("清除 TCP 网站数据？", isPresented: $confirmsClear) {
                Button("清除并关闭当前网页", role: .destructive) { Task { await browser.clearData() } }
            } message: {
                Text("这会退出 TCP 中已登录的网站。")
            }
    }
}
