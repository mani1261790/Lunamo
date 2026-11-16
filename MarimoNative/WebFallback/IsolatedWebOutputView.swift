import AppKit
import MarimoDomain
import MarimoOutput
import SwiftUI
import WebKit

struct IsolatedWebOutputView: NSViewRepresentable {
  let payload: WebOutputPayload
  let internalScrollingEnabled: Bool
  @Binding var contentHeight: CGFloat
  @Binding var failure: String?

  func makeCoordinator() -> Coordinator {
    Coordinator(contentHeight: $contentHeight, failure: $failure)
  }

  func makeNSView(context: Context) -> WKWebView {
    let webView = WebOutputPool.shared.acquire()
    context.coordinator.attach(to: webView)
    configure(webView, coordinator: context.coordinator)
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    Self.configureScrolling(in: webView, enabled: internalScrollingEnabled)
    let overflow = internalScrollingEnabled ? "auto" : "hidden"
    webView.evaluateJavaScript(
      "document.documentElement.style.overflow='\(overflow)';document.body.style.overflow='\(overflow)'"
    )
  }

  static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
    coordinator.detach(from: webView)
    WebOutputPool.shared.release(webView)
  }

  private func configure(_ webView: WKWebView, coordinator: Coordinator) {
    webView.underPageBackgroundColor = .clear
    Self.configureScrolling(in: webView, enabled: internalScrollingEnabled)

    let controller = webView.configuration.userContentController
    controller.removeAllUserScripts()
    controller.removeAllContentRuleLists()
    controller.removeScriptMessageHandler(forName: "contentHeight")
    controller.add(coordinator, name: "contentHeight")
    controller.addUserScript(
      WKUserScript(
        source: Self.heightScript,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
      )
    )
    coordinator.load(payload, in: webView)
  }

  private static func configureScrolling(in webView: WKWebView, enabled: Bool) {
    (webView as? CellOutputWebView)?.internalScrollingEnabled = enabled
    guard let scrollView = descendantScrollView(in: webView) else { return }
    scrollView.hasVerticalScroller = enabled
    scrollView.hasHorizontalScroller = false
    scrollView.verticalScrollElasticity = enabled ? .automatic : .none
    scrollView.horizontalScrollElasticity = .none
  }

  private static func descendantScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView { return scrollView }
    for child in view.subviews {
      if let scrollView = descendantScrollView(in: child) { return scrollView }
    }
    return nil
  }

  private static let heightScript = """
    (() => {
      const report = () => {
        const height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
        window.webkit.messageHandlers.contentHeight.postMessage(height);
      };
      new ResizeObserver(report).observe(document.documentElement);
      new MutationObserver(report).observe(document.documentElement, {subtree: true, childList: true, attributes: true});
      report();
    })();
    """

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var contentHeight: Binding<CGFloat>
    private var failure: Binding<String?>
    private var document: WebOutputDocument?
    private var allowsPageJavaScript = false

    init(contentHeight: Binding<CGFloat>, failure: Binding<String?>) {
      self.contentHeight = contentHeight
      self.failure = failure
    }

    func attach(to webView: WKWebView) {
      webView.navigationDelegate = self
      webView.uiDelegate = self
    }

    func detach(from webView: WKWebView) {
      webView.configuration.userContentController.removeScriptMessageHandler(
        forName: "contentHeight"
      )
      cleanupDocument()
    }

    func load(_ payload: WebOutputPayload, in webView: WKWebView) {
      cleanupDocument()
      allowsPageJavaScript = payload.allowsJavaScript
      do {
        let document = try WebOutputDocumentBuilder.build(payload)
        self.document = document
        installNetworkBlock(in: webView) { [weak self, weak webView] result in
          guard let self, let webView else { return }
          switch result {
          case .success:
            webView.loadFileURL(
              document.indexURL,
              allowingReadAccessTo: document.directoryURL
            )
          case .failure(let error):
            self.failure.wrappedValue = "Network isolation could not be installed: \(error)"
          }
        }
      } catch {
        failure.wrappedValue = "Web output could not be prepared: \(error)"
      }
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard message.name == "contentHeight", let height = message.body as? NSNumber else { return }
      contentHeight.wrappedValue = max(1, min(CGFloat(height.doubleValue), 100_000))
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
      preferences.allowsContentJavaScript = allowsPageJavaScript
      guard let url = navigationAction.request.url else {
        return (.cancel, preferences)
      }
      if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
        confirmExternalNavigation(url)
        return (.cancel, preferences)
      } else if url.isFileURL || url.scheme == "about" {
        return (.allow, preferences)
      } else {
        return (.cancel, preferences)
      }
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
      guard let url = navigationResponse.response.url, url.isFileURL || url.scheme == "about" else {
        return .cancel
      }
      return .allow
    }

    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if let url = navigationAction.request.url { confirmExternalNavigation(url) }
      return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      MarimoLog.web.error("Web content process stopped")
      failure.wrappedValue =
        "This web output stopped unexpectedly. The notebook and kernel are unchanged."
    }

    private func installNetworkBlock(
      in webView: WKWebView,
      completion: @escaping (Result<Void, Error>) -> Void
    ) {
      let rules = """
        [
          {"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
          {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}
        ]
        """
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "MarimoNative.BlockNetwork.v1",
        encodedContentRuleList: rules
      ) { ruleList, error in
        Task { @MainActor in
          if let ruleList {
            webView.configuration.userContentController.add(ruleList)
            completion(.success(()))
          } else {
            completion(.failure(error ?? WebOutputIsolationError.ruleCompilationFailed))
          }
        }
      }
    }

    private func confirmExternalNavigation(_ url: URL) {
      guard url.scheme == "https" || url.scheme == "http" else { return }
      let alert = NSAlert()
      alert.messageText = String(localized: "Open Link in Browser?")
      alert.informativeText = url.absoluteString
      alert.addButton(withTitle: String(localized: "Open"))
      alert.addButton(withTitle: String(localized: "Cancel"))
      if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
    }

    private func cleanupDocument() {
      guard let document else { return }
      TemporaryOutputStore.shared.removeDocumentDirectory(document.directoryURL)
      self.document = nil
    }
  }
}

enum WebOutputIsolationError: Error {
  case ruleCompilationFailed
}
