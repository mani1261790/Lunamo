import MarimoDomain

public enum OutputRendererKind: String, Sendable, Equatable {
  case text
  case json
  case error
  case traceback
  case image
  case csv
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
    "application/vnd.marimonative+renderer-error": .failure,
  ]
}
