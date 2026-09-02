import Foundation

extension NotebookStore {
  public func cancelSaveConflict() {
    dismissConflictBanner()
  }

  public func reloadConflictedDocument() async {
    await reloadPresentedFile()
  }

  public func dismissSaveMessage() {
    saveMessage = nil
  }

  public func reportSaveFailure(_ error: any Error) {
    saveMessage = "Save failed: \(error.localizedDescription)"
    presentError(
      code: error is AtomicWriteError ? .documentSave : .lspProtocol,
      cause: error.localizedDescription,
      target: document.sourceURL?.path ?? document.notebookURI,
      recoveryActions: ["Retry", "Save As"]
    )
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
