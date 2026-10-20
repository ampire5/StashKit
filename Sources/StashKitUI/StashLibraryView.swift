import AppKit
import OSLog
import WebKit
@_exported import StashKit

/// A scene the Stash page handed over: its files as Stash wrote them, where Stash says it was left,
/// and whether it was opened from a list that the next/previous keys can step through.
public struct StashScene: Equatable, Sendable {
    public let id: String
    public let paths: [String]
    public let resumeTime: Double
    public let duration: Double
    public let hasQueue: Bool
    /// Sent when the page opened with `autoplay=true` (after a queue step), not by a click on the cover.
    public let automatic: Bool

    public init?(message body: Any) {
        guard let body = body as? [String: Any], body["type"] as? String == "open",
              let id = body["sceneID"] as? String, let paths = body["paths"] as? [String] else { return nil }
        self.id = id
        self.paths = paths
        resumeTime = (body["resumeTime"] as? NSNumber)?.doubleValue ?? 0
        duration = (body["duration"] as? NSNumber)?.doubleValue ?? 0
        hasQueue = body["hasQueue"] as? Bool ?? false
        automatic = body["automatic"] as? Bool ?? false
    }
}

/// The Stash WebUI, extended by the interceptors the app chooses (for example `StashInterceptor.scenePlayer`).
/// Created the first time the app shows Stash and kept until quit, so going back finds the same page at the same
/// scroll position.
public final class StashLibraryView: NSView, WKNavigationDelegate, WKUIDelegate {
    /// Called when a page load finished (the app's startup trace marks "stash page loaded" here).
    public var onPageLoaded: (() -> Void)?
    public private(set) var isLoadFailed = false

    public let url: URL
    private let interceptors: [StashInterceptor]
    private let webView: WKWebView
    private let failure = NSStackView()
    private let failureText = NSTextField(labelWithString: "")
    private static let logger = Logger(subsystem: "local.stashkit", category: "Stash")

    public init(url: URL, interceptors: [StashInterceptor]) {
        self.url = url
        self.interceptors = interceptors
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // Stash keeps its list filters and views in local storage
        for interceptor in interceptors {
            configuration.userContentController.addUserScript(
                WKUserScript(source: interceptor.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        // The content controller keeps its handler; a weak hop avoids a cycle through the web view.
        configuration.userContentController.add(MessageRelay(self), name: StashBridgeScript.handlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        setUpFailure()
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor), webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor), webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            failure.centerXAnchor.constraint(equalTo: centerXAnchor), failure.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        load()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Steps Stash's queue from the scene page (+1 next, −1 previous). Stash then opens the neighbour with
    /// `autoplay=true` and the bridge sends it as an automatic scene; nothing comes at the end of the list.
    /// Needs the `scenePlayer` interceptor: it defines the page functions this calls (otherwise nothing happens).
    public func step(_ direction: Int) {
        let call = direction > 0 ? "next" : "previous"
        webView.evaluateJavaScript("window.__framescrub && window.__framescrub.\(call) && window.__framescrub.\(call)()") { _, error in
            if let error { Self.logger.error("queue step \(call, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Back and forward in the page's history, for buttons the app reads itself (AppKit never sees them, so the
    /// view's own monitor for the mouse's back and forward buttons cannot): for example a mouse's side buttons taken
    /// over HID++.
    public func goBack() { webView.goBack() }
    public func goForward() { webView.goForward() }

    /// The scene on the page was deleted: leave its page. Meant for the `scenePlayer` interceptor's setup, but works
    /// on any page.
    public func leaveDeletedScene() {
        if webView.canGoBack { webView.goBack() } else { webView.load(URLRequest(url: url.appendingPathComponent("scenes"))) }
    }

    /// Goes to `path` (`/galleries/12`) inside the page, the way a click on a link does: no reload, the page keeps
    /// its state.
    public func navigate(to path: String) {
        let quoted = (try? JSONSerialization.data(withJSONObject: [path])).flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"/\""
        webView.evaluateJavaScript("window.history.pushState({}, '', \(quoted)); "
                                   + "window.dispatchEvent(new PopStateEvent('popstate'))") { _, error in
            if let error { Self.logger.error("navigate failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    public func focusPage() {
        window?.makeFirstResponder(webView)
    }

    // MARK: Browser keys and buttons

    /// ⌘[ ⌘] back and forward, ⌘R reload, as in a browser. They come here only when the page did not use them.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden, window?.firstResponder.map(isInside) == true,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "[": webView.goBack(); return true
        case "]": webView.goForward(); return true
        case "r": webView.reload(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    /// ⌘← ⌘→ arrive here when the page did not use them (in a text field they move the caret).
    public override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]) == .command else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 123: webView.goBack()
        case 124: webView.goForward()
        default: super.keyDown(with: event)
        }
    }

    /// The mouse's back and forward buttons over the page.
    private var mouseButtons: Any?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseButtons { NSEvent.removeMonitor(mouseButtons) }
        mouseButtons = nil
        guard window != nil else { return }
        mouseButtons = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self, !isHidden, event.window === window,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
            switch event.buttonNumber {
            case 3: webView.goBack(); return nil
            case 4: webView.goForward(); return nil
            default: return event
            }
        }
    }

    private func isInside(_ responder: NSResponder) -> Bool {
        (responder as? NSView)?.isDescendant(of: self) == true
    }

    // MARK: WKUIDelegate

    /// Links that open a new window (Stash's links to performer, studio and scene sites) go to the default browser.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    public func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window else { completionHandler(nil); return }
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    private func load() {
        isLoadFailed = false
        failure.isHidden = true
        webView.load(URLRequest(url: url))
    }

    private func setUpFailure() {
        failureText.textColor = .white
        failureText.font = .systemFont(ofSize: 15)
        let retry = NSButton(title: "Retry", target: self, action: #selector(retry(_:)))
        failure.orientation = .vertical
        failure.spacing = 12
        failure.addArrangedSubview(failureText)
        failure.addArrangedSubview(retry)
        failure.translatesAutoresizingMaskIntoConstraints = false
        failure.isHidden = true
        addSubview(failure)
    }

    @objc private func retry(_ sender: Any?) { load() }

    private func showFailure(_ error: Error) {
        Self.logger.error("Stash page failed: \(error.localizedDescription, privacy: .public)")
        isLoadFailed = true
        failureText.stringValue = "Stash is not responding: \(url.absoluteString)"
        failure.isHidden = false
    }

    /// Only Stash's own page may hand scenes over: another site in this view must not make the app mount shares.
    fileprivate func received(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame,
              StashPathMap.isStashPage(scheme: origin.protocol, host: origin.host, port: origin.port, stashURL: url) else {
            Self.logger.error("Stash bridge: message from \(origin.protocol, privacy: .public)://\(origin.host, privacy: .public) ignored")
            return
        }
        // Each interceptor in turn, until one takes the message.
        if !interceptors.contains(where: { $0.handle(message.body) }) {
            Self.logger.error("Stash bridge: message not taken by any interceptor, dropped")
        }
    }

    // MARK: WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showFailure(error) }
    }

    /// The page stays on Stash: a link to another site opens in the default browser.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let target = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame != false,
           let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https",
           !StashPathMap.isStashPage(scheme: scheme, host: target.host ?? "", port: target.port ?? 0, stashURL: url) {
            NSWorkspace.shared.open(target)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        failure.isHidden = true
        onPageLoaded?()
    }
}

private final class MessageRelay: NSObject, WKScriptMessageHandler {
    weak var target: StashLibraryView?
    init(_ target: StashLibraryView) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.received(message)
    }
}
