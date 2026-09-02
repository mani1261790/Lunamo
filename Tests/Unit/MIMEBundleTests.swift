import Foundation
import MarimoDomain
import MarimoOutput
import Testing

@testable import MarimoWebFallback

@Suite("MIME bundle and isolated web output")
struct MIMEBundleTests {
  @Test("Golden precedence and HTML hiding rules are deterministic")
  func htmlPrecedenceGolden() throws {
    let entries = Dictionary(
      uniqueKeysWithValues: [
        "text/plain", "video/mpeg", "application/json", "text/csv", "text/latex",
        "text/markdown", "image/gif", "image/jpeg", "image/png", "image/svg+xml",
        "application/vnd.vega.v5+json", "application/vnd.vega.v6+json",
        "application/vnd.vegalite.v5+json", "application/vnd.vegalite.v6+json", "text/html",
        "image/avif", "image/bmp", "image/tiff", "application/x-extra",
      ].map { ($0, JSONValue.string($0)) }
    )
    let bundle = try MIMEBundleResolver.resolve(mimeBundle(entries))
    #expect(
      bundle.representations.map(\.mimeType) == [
        "text/html",
        "application/vnd.vegalite.v6+json",
        "application/vnd.vegalite.v5+json",
        "application/vnd.vega.v6+json",
        "application/vnd.vega.v5+json",
        "image/svg+xml",
        "text/markdown",
        "text/latex",
        "text/csv",
        "application/json",
        "text/plain",
        "video/mpeg",
        "application/x-extra",
      ]
    )
  }

  @Test("Vega hides raster fallbacks but preserves other selectable formats")
  func vegaHidingGolden() throws {
    let bundle = try MIMEBundleResolver.resolve(
      mimeBundle([
        "image/png": .string("png"),
        "image/jpeg": .string("jpeg"),
        "image/gif": .string("gif"),
        "image/tiff": .string("tiff"),
        "text/plain": .string("plain"),
        "application/vnd.vegalite.v6+json": .object(["mark": .string("bar")]),
      ])
    )
    #expect(
      bundle.representations.map(\.mimeType) == [
        "application/vnd.vegalite.v6+json", "text/plain", "image/tiff",
      ]
    )
  }

  @Test("Metadata is separated and only valid positive display dimensions survive")
  func metadataDimensions() throws {
    let bundle = try MIMEBundleResolver.resolve(
      mimeBundle([
        "image/png": .string("png"),
        "text/plain": .string("plain"),
        "__metadata__": .object([
          "image/png": .object(["width": .integer(640), "height": .number(360.5)]),
          "text/plain": .object(["width": .integer(0), "height": .integer(100_001)]),
        ]),
      ])
    )
    let image = try #require(bundle.representations.first { $0.mimeType == "image/png" })
    #expect(image.displaySize == OutputDisplaySize(width: 640, height: 360.5))
    let plain = try #require(bundle.representations.first { $0.mimeType == "text/plain" })
    #expect(plain.displaySize == nil)
    guard case .object = bundle.metadata else {
      Issue.record("Expected separated MIME metadata")
      return
    }
  }

  @Test("Common HTML and standard repr fixtures remain native")
  func standardReprUsesNativeHTML() {
    let fixtures = [
      "<pre>1</pre>",
      "<pre>1.5</pre>",
      "<span>&quot;value&quot;</span>",
      "<pre><code>[1, 2]</code></pre>",
      "<pre>{&#39;answer&#39;: 42}<br></pre>",
    ]
    for fixture in fixtures {
      let prepared = OutputPreparationService.prepareSynchronously(
        MarimoOutput(channel: .output, mimeType: "text/html", data: .string(fixture))
      )
      guard case .nativeHTML(let text) = prepared else {
        Issue.record("Standard repr unexpectedly required a web view: \(fixture)")
        continue
      }
      #expect(!text.isEmpty)
    }
  }

  @Test("Unsafe or unknown HTML never enters the native subset")
  func strictNativeHTMLSubset() {
    #expect(HTMLNativeSubsetDecoder.decode("<script>alert(1)</script>") == nil)
    #expect(HTMLNativeSubsetDecoder.decode("<strong>unknown</strong>") == nil)
    #expect(HTMLNativeSubsetDecoder.decode("<span onclick='x()'>event</span>") == nil)
    #expect(HTMLNativeSubsetDecoder.decode("<pre>a<br>b</pre>") == "a\nb")
  }

  @Test("Markdown and SVG are sanitized before isolated rendering")
  func fallbackSanitization() throws {
    let markdown = WebOutputSanitizer.markdown("<script>alert(1)</script>")
    #expect(markdown.contains("&lt;script&gt;"))
    #expect(!markdown.contains("<script>"))

    let svg = try WebOutputSanitizer.svg(
      "<svg xmlns='http://www.w3.org/2000/svg' onload='x()'><script>x()</script><a href='https://example.com'><text>safe</text></a></svg>"
    )
    #expect(!svg.lowercased().contains("script"))
    #expect(!svg.lowercased().contains("onload"))
    #expect(!svg.contains("https://example.com"))
    #expect(svg.contains("safe"))
  }

  @Test("Bundled Vega and KaTeX documents contain no CDN dependency")
  func bundledRendererDocuments() throws {
    for payload in [
      WebOutputPayload(kind: .latex, content: "x^2", allowsJavaScript: true, displaySize: nil),
      WebOutputPayload(
        kind: .vega,
        content: "{\"mark\":\"bar\"}",
        allowsJavaScript: true,
        displaySize: nil
      ),
    ] {
      let document = try WebOutputDocumentBuilder.build(payload)
      defer { try? FileManager.default.removeItem(at: document.directoryURL) }
      let html = try String(contentsOf: document.indexURL, encoding: .utf8)
      #expect(html.contains("connect-src 'none'"))
      #expect(!html.contains("https://"))
      #expect(!html.contains("http://"))
      #expect(FileManager.default.fileExists(atPath: document.directoryURL.path))
    }
  }

  @Test("Web output pool retains at most two offscreen views")
  @MainActor
  func boundedWebOutputPool() {
    let pool = WebOutputPool()
    let views = [pool.acquire(), pool.acquire(), pool.acquire()]
    #expect(pool.retainedCount <= pool.retainedLimit)
    for view in views { pool.release(view) }
    #expect(pool.visibleCount == 0)
    #expect(pool.retainedCount == WebOutputPool.offscreenReserve)
    #expect(pool.retainedCount <= pool.retainedLimit)
  }

  private func mimeBundle(_ entries: [String: JSONValue]) -> MarimoOutput {
    MarimoOutput(
      channel: .output,
      mimeType: MIMEBundleResolver.mimeType,
      data: .object(entries)
    )
  }
}
