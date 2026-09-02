import Foundation

public struct NotebookDocumentState: Sendable, Equatable {
  public var sourceURL: URL?
  public var cells: [NotebookCellState]
  public var sourceRevision: UInt64
  public var dirty: Bool
  public var selectedCellID: UUID?

  public init(
    sourceURL: URL? = nil,
    cells: [NotebookCellState] = [NotebookCellState()],
    sourceRevision: UInt64 = 0,
    dirty: Bool = false,
    selectedCellID: UUID? = nil
  ) {
    self.sourceURL = sourceURL
    self.cells = cells
    self.sourceRevision = sourceRevision
    self.dirty = dirty
    self.selectedCellID = selectedCellID ?? cells.first?.runtimeID
  }
}
