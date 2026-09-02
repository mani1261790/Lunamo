import MarimoDomain

public struct DocumentSnapshot: Sendable, Equatable {
  public let state: NotebookDocumentState

  public init(state: NotebookDocumentState) {
    self.state = state
  }
}
