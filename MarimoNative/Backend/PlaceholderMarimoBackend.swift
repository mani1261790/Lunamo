import MarimoDomain

public actor PlaceholderMarimoBackend: MarimoBackend {
  public init() {}

  public func status() async -> BackendStatus {
    .unavailable
  }

  public func start() async throws {}

  public func parseNotebook(source _: String) async throws -> NotebookParseOutcome {
    .convertible
  }

  public func shutdown() async {}
}
