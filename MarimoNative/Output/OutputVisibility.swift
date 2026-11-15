import Foundation
import MarimoDomain

public enum OutputVisibility {
  public static func hasRenderableContent(_ output: MarimoOutput) -> Bool {
    switch OutputRendererRegistry().renderer(for: output.mimeType) {
    case .error:
      guard case .array(let errors) = output.data else { return true }
      return !errors.isEmpty
    case .text, .traceback, .html:
      guard case .string(let text) = output.data else { return true }
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .webFallback:
      let mimeType = output.mimeType.lowercased()
      guard ["image/svg+xml", "text/markdown", "text/latex"].contains(mimeType),
        case .string(let text) = output.data
      else { return true }
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .json, .image, .csv, .mimeBundle, .failure, .unsupported:
      return true
    }
  }
}
