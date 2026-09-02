import WebKit

final class CellOutputWebView: WKWebView {
  var internalScrollingEnabled = false

  override func scrollWheel(with event: NSEvent) {
    if internalScrollingEnabled {
      super.scrollWheel(with: event)
    } else {
      nextResponder?.scrollWheel(with: event)
    }
  }
}

@MainActor
final class WebOutputPool {
  static let shared = WebOutputPool()
  static let offscreenReserve = 2

  private var spares: [WKWebView] = []
  private(set) var visibleCount = 0

  var retainedLimit: Int { visibleCount + Self.offscreenReserve }
  var retainedCount: Int { visibleCount + spares.count }

  func acquire() -> WKWebView {
    visibleCount += 1
    return spares.popLast()
      ?? CellOutputWebView(frame: .zero, configuration: Self.configuration())
  }

  func release(_ webView: WKWebView) {
    visibleCount = max(0, visibleCount - 1)
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.configuration.userContentController.removeAllUserScripts()
    webView.configuration.userContentController.removeAllContentRuleLists()
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentHeight")
    if spares.count < Self.offscreenReserve {
      spares.append(webView)
    }
  }

  private static func configuration() -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    return configuration
  }
}
