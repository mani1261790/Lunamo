import Foundation
import MarimoDomain

extension NotebookStore {
  public func pythonCompletions(source: String, line: Int, column: Int) async
    -> [PythonCompletionItem]
  {
    guard backendStatus == .ready, !source.isEmpty else { return [] }
    return (try? await backend.completePython(source: source, line: line, column: column)) ?? []
  }

  public func updateCodeSelection(cellID: UUID, selection: String?) {
    let normalized = selection?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalized, !normalized.isEmpty {
      codeSelections[cellID] = normalized
    } else {
      codeSelections.removeValue(forKey: cellID)
    }
  }
}
