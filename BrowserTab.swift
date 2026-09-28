import Foundation
import WebKit

final class BrowserTab: Identifiable {
    let id: UUID
    let webView: WKWebView
    var title: String
    var urlString: String

    init(id: UUID = UUID(), webView: WKWebView, title: String = "Nieuwe tab", urlString: String = "") {
        self.id = id
        self.webView = webView
        self.title = title
        self.urlString = urlString
    }
}
