import Foundation
import MarimoDomain

enum NotebookRuntimeErrorContext {
  static func runtimeErrorContext(for cell: NotebookCellState) -> String? {
    let outputs = ([cell.runtime.output].compactMap { $0 } + cell.runtime.console)
      .filter { output in
        output.channel == .stderr || output.channel == .marimoError
          || output.mimeType.localizedCaseInsensitiveContains("error")
          || output.mimeType.localizedCaseInsensitiveContains("traceback")
      }
      .compactMap(errorText)
    guard !outputs.isEmpty else { return nil }
    return String(outputs.joined(separator: "\n\n").prefix(6_000))
  }

  private static func errorText(_ output: MarimoOutput) -> String? {
    if case .string(let text) = output.data {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    guard let data = try? JSONEncoder().encode(output.data),
      let text = String(data: data, encoding: .utf8), text != "[]"
    else { return nil }
    return text
  }
}
