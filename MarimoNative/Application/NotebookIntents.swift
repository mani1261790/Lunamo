import Foundation
import MarimoDomain

public enum NotebookIntent: Sendable, Equatable {
  case addCell
  case insertCell(after: UUID?)
  case insertCellAt(Int)
  case insertTextCellAt(Int)
  case updateMarkdown(cellID: UUID, markdown: String)
  case deleteCell(UUID)
  case duplicateCell(UUID)
  case moveCell(UUID, to: Int)
  case selectCell(UUID)
  case updateCode(cellID: UUID, code: String)
  case updateComposedCode(cellID: UUID, code: String, hasMarkedText: Bool)
  case updateName(cellID: UUID, name: String)
  case updateConfiguration(cellID: UUID, configuration: CellConfiguration)
  case updateMetadata([String: JSONValue])
  case updateAppOptions(AppOptions)
  case updateHeader(String?)
  case updateRuntime(cellID: UUID, runtime: CellRuntimeState)
  case setKernelSessionID(String?)
  case runCell(cellID: UUID, executable: String, workingDirectory: String)
  case runAll(executable: String, workingDirectory: String)
}
