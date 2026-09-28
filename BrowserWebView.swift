import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var browser: BrowserModel

    func makeUIView(context: Context) -> WKWebView {
        browser.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
