import Foundation
import MarimoDomain
import MarimoOutput

struct WebOutputDocument {
  let directoryURL: URL
  let indexURL: URL
}

enum WebOutputDocumentBuilder {
  static func build(_ payload: WebOutputPayload) throws -> WebOutputDocument {
    let directory = try TemporaryOutputStore.shared.makeDocumentDirectory()
    do {
      let body = try body(for: payload, in: directory)
      let index = directory.appending(path: "index.html")
      try Data(document(body: body, allowsUnsafeEval: payload.kind == .vega).utf8)
        .write(to: index, options: .atomic)
      return WebOutputDocument(directoryURL: directory, indexURL: index)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  private static func body(for payload: WebOutputPayload, in directory: URL) throws -> String {
    switch payload.kind {
    case .html, .markdown, .svg:
      return payload.content
    case .latex:
      try copyAsset("katex.min.js", to: directory)
      try copyAsset("katex.min.css", to: directory)
      try copyAsset("fonts", to: directory)
      try copyAsset("render-latex.js", to: directory)
      return """
        <link rel="stylesheet" href="katex.min.css">
        <div id="math-output" data-source="\(base64(payload.content))"></div>
        <script src="katex.min.js"></script>
        <script src="render-latex.js"></script>
        """
    case .vega:
      for asset in ["vega.min.js", "vega-lite.min.js", "vega-embed.min.js", "render-vega.js"] {
        try copyAsset(asset, to: directory)
      }
      return """
        <div id="vega-output" data-source="\(base64(payload.content))"></div>
        <script src="vega.min.js"></script>
        <script src="vega-lite.min.js"></script>
        <script src="vega-embed.min.js"></script>
        <script src="render-vega.js"></script>
        """
    }
  }

  private static func document(body: String, allowsUnsafeEval: Bool) -> String {
    let scriptPolicy = allowsUnsafeEval ? "'self' 'unsafe-eval'" : "'self'"
    return """
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; media-src data: blob:; font-src 'self'; style-src 'self' 'unsafe-inline'; script-src \(scriptPolicy); connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          html, body { margin: 0; padding: 0; overflow: hidden; background: transparent; color: CanvasText; }
          body { font: 13px -apple-system, BlinkMacSystemFont, sans-serif; overflow-wrap: anywhere; }
          pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; white-space: pre-wrap; }
          img, svg, video, canvas { max-width: 100%; height: auto; }
        </style>
      </head>
      <body>\(body)</body>
      </html>
      """
  }

  private static func copyAsset(_ name: String, to directory: URL) throws {
    guard let resourceRoot = Bundle.module.resourceURL else {
      throw WebOutputDocumentError.missingAsset(name)
    }
    let source = resourceRoot.appending(path: "Assets").appending(path: name)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw WebOutputDocumentError.missingAsset(name)
    }
    try FileManager.default.copyItem(at: source, to: directory.appending(path: name))
  }

  private static func base64(_ source: String) -> String {
    Data(source.utf8).base64EncodedString()
  }
}

enum WebOutputDocumentError: Error {
  case missingAsset(String)
}
