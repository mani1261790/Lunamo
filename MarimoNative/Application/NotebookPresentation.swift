import Foundation

extension NotebookStore {
  public func cancelSaveConflict() {
    saveConflictURL = nil
  }

  public func reloadConflictedDocument() async {
    guard let target = saveConflictURL else { return }
    saveConflictURL = nil
    await open(target)
  }

  public func dismissSaveMessage() {
    saveMessage = nil
  }

  public func reportSaveFailure(_ error: any Error) {
    saveMessage = "Save failed: \(error.localizedDescription)"
  }

  public func focusEditor(_ cellID: UUID) {
    guard document.cells.contains(where: { $0.runtimeID == cellID }) else { return }
    document.selectedCellID = cellID
    focusedCellID = cellID
  }

  public func leaveEditor() {
    focusedCellID = nil
  }
}
