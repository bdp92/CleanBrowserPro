import Foundation
import WebKit

enum ContentBlockerService {
    enum BlockerError: LocalizedError {
        case missingRules

        var errorDescription: String? {
            "De ingebouwde blokkeerlijst kon niet worden geladen."
        }
    }

    @MainActor
    static func install(on controller: WKUserContentController, strict: Bool) async throws {
        controller.removeAllContentRuleLists()

        let filename = strict ? "blocker-strict" : "blocker-base"
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else {
            throw BlockerError.missingRules
        }

        let identifier = strict ? "CleanBrowserPro.Strict.v1" : "CleanBrowserPro.Base.v1"
        let store = WKContentRuleListStore.default()

        let compiled: WKContentRuleList? = try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) { list, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: list)
                }
            }
        }

        if let compiled {
            controller.add(compiled)
        }
    }
}
