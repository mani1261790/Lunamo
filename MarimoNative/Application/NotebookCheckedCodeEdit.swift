import Foundation

public enum CheckedCodeEditState: Sendable, Equatable {
  case ready
  case alreadyApplied
  case missingCell
  case sourceChanged
  case textCell
}

extension NotebookStore {
  public func checkedCodeEditState(
    cellID: UUID,
    expectedCode: String,
    replacementCode: String
  ) -> CheckedCodeEditState {
    guard let cell = document.cells.first(where: { $0.runtimeID == cellID }) else {
      return .missingCell
    }
    guard cell.editor.markdown == nil else { return .textCell }
    if cell.code == replacementCode { return .alreadyApplied }
    guard cell.code == expectedCode else { return .sourceChanged }
    return .ready
  }

  @discardableResult
  public func applyCheckedCodeEdit(
    cellID: UUID,
    expectedCode: String,
    replacementCode: String
  ) async -> CheckedCodeEditState {
    let state = checkedCodeEditState(
      cellID: cellID,
      expectedCode: expectedCode,
      replacementCode: replacementCode
    )
    guard state == .ready else { return state }
    await send(.updateCode(cellID: cellID, code: replacementCode))
    return checkedCodeEditState(
      cellID: cellID,
      expectedCode: expectedCode,
      replacementCode: replacementCode
    ) == .alreadyApplied ? .alreadyApplied : .sourceChanged
  }
}
