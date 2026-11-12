import SwiftUI
import WebKit

/// The M7 web interface for the trip steps that phase 2 and 3 move into the native app.
/// Only 127.0.0.1 is allowed; nothing is loaded from the internet.
struct ClassicWebView: NSViewRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('macapp-embedded')", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let u = action.request.url
            decisionHandler(u?.host == "127.0.0.1" || ["about", "blob", "data"].contains(u?.scheme ?? "") ? .allow : .cancel)
        }
    }
}
