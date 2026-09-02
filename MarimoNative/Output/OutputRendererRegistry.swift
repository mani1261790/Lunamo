import MarimoDomain

public enum OutputRendererKind: String, Sendable, Equatable {
  case text
  case json
  case error
  case traceback
  case image
  case csv
  case html
  case mimeBundle
  case webFallback
  case failure
  case unsupported
}

public struct OutputRendererRegistry: Sendable {
  private let renderers: [String: OutputRendererKind]

  public init(renderers: [String: OutputRendererKind] = Self.nativeRenderers) {
    self.renderers = renderers
  }

  public func renderer(for mimeType: String) -> OutputRendererKind {
    renderers[mimeType.lowercased()] ?? .unsupported
  }

  public static let nativeRenderers: [String: OutputRendererKind] = [
    "text/plain": .text,
    "text/password": .text,
    "text/x-marimonative-truncation-notice": .text,
    "application/json": .json,
    "application/vnd.marimo+error": .error,
    "application/vnd.marimo+traceback": .traceback,
    "image/png": .image,
    "image/jpeg": .image,
    "image/gif": .image,
    "image/tiff": .image,
    "image/bmp": .image,
    "image/avif": .image,
    "text/csv": .csv,
    "text/html": .html,
    "application/vnd.marimo+mimebundle": .mimeBundle,
    "image/svg+xml": .webFallback,
    "text/markdown": .webFallback,
    "text/latex": .webFallback,
    "application/vnd.vegalite.v6+json": .webFallback,
    "application/vnd.vegalite.v5+json": .webFallback,
    "application/vnd.vega.v6+json": .webFallback,
    "application/vnd.vega.v5+json": .webFallback,
    "application/vnd.marimonative+renderer-error": .failure,
  ]
}
