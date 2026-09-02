import Foundation
import MarimoOutput
import SwiftUI
import Testing
import WebKit

@testable import MarimoWebFallback

@Suite("Bundled web renderers")
@MainActor
struct WebRendererTests {
  @Test("Local KaTeX and Vega assets render with a non-persistent store")
  func bundledAssetsRender() async throws {
    let cases: [(WebOutputPayload, String)] = [
      (
        WebOutputPayload(
          kind: .latex,
          content: "x^2 + y^2 = z^2",
          allowsJavaScript: true,
          displaySize: nil
        ),
        "#math-output .katex"
      ),
      (
        WebOutputPayload(
          kind: .vega,
          content:
            "{\"data\":{\"values\":[{\"x\":\"A\",\"y\":2}]},\"mark\":\"bar\",\"encoding\":{\"x\":{\"field\":\"x\",\"type\":\"nominal\"},\"y\":{\"field\":\"y\",\"type\":\"quantitative\"}}}",
          allowsJavaScript: true,
          displaySize: nil
        ),
        "#vega-output svg"
      ),
    ]

    for (payload, selector) in cases {
      let document = try WebOutputDocumentBuilder.build(payload)
      defer { try? FileManager.default.removeItem(at: document.directoryURL) }
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = true
      let webView = WKWebView(
        frame: .init(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
      webView.loadFileURL(document.indexURL, allowingReadAccessTo: document.directoryURL)

      let deadline = ContinuousClock.now.advanced(by: .seconds(8))
      var rendered = false
      while ContinuousClock.now < deadline {
        if let value = try? await webView.evaluateJavaScript(
          "Boolean(document.querySelector('\(selector)'))"
        ), let value = value as? Bool, value {
          rendered = true
          break
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
      if !rendered {
        let diagnostic = try? await webView.evaluateJavaScript(
          "document.body.innerText + ' | vega=' + typeof vega + ' embed=' + typeof vegaEmbed"
        )
        Issue.record(
          "Bundled renderer did not create \(selector): \(String(describing: diagnostic))")
      }
      webView.stopLoading()
    }
  }

  @Test("Production cell-local host loads only its isolated output subtree")
  func productionHostLoadsOutput() async throws {
    let payload = WebOutputPayload(
      kind: .html,
      content:
        "<script>document.body.dataset.executed='true'</script><strong id='isolated'>cell-local output</strong>",
      allowsJavaScript: false,
      displaySize: nil
    )
    let hostingView = NSHostingView(rootView: CellWebOutputView(payload: payload))
    hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
    hostingView.layoutSubtreeIfNeeded()

    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    var webView: WKWebView?
    while ContinuousClock.now < deadline {
      hostingView.layoutSubtreeIfNeeded()
      webView = descendantWebView(in: hostingView)
      if webView != nil { break }
      try? await Task.sleep(for: .milliseconds(25))
    }
    let isolatedWebView = try #require(webView)
    var rendered = false
    while ContinuousClock.now < deadline {
      if let value = try? await isolatedWebView.evaluateJavaScript(
        "document.getElementById('isolated')?.textContent"
      ), let value = value as? String, value == "cell-local output" {
        rendered = true
        break
      }
      try? await Task.sleep(for: .milliseconds(25))
    }
    #expect(rendered)
    let pageScriptExecuted =
      try? await isolatedWebView.evaluateJavaScript(
        "document.body.dataset.executed === 'true'"
      ) as? Bool
    #expect(pageScriptExecuted != true)
    #expect(isolatedWebView.url?.isFileURL == true)
    #expect((isolatedWebView as? CellOutputWebView)?.internalScrollingEnabled == false)
    isolatedWebView.stopLoading()
  }

  private func descendantWebView(in view: NSView) -> WKWebView? {
    if let webView = view as? WKWebView { return webView }
    for child in view.subviews {
      if let webView = descendantWebView(in: child) { return webView }
    }
    return nil
  }
}
