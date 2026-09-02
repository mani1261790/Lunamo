import Foundation

extension NotebookStore {
  public enum OpenState: Sendable, Equatable {
    case idle
    case loading(URL)
    case loaded(URL)
    case invalidSyntax(URL, line: Int?, column: Int?)
    case convertible(URL)
    case failed(URL, String)
  }

  public enum SaveOutcome: Sendable, Equatable {
    case unchanged
    case needsDestination
    case saved(URL)
    case savedWithSessionReset(URL)
  }
}

public enum NotebookStoreError: Error, Sendable, Equatable {
  case compositionActive(UUID)
  case environmentNotReady
  case environmentMismatch
  case executionNotTrusted
  case noCellsToExecute
}
