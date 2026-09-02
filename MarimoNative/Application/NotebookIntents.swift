import Foundation

public enum NotebookIntent: Sendable, Equatable {
  case addCell
  case selectCell(UUID)
  case updateCode(cellID: UUID, code: String)
}
