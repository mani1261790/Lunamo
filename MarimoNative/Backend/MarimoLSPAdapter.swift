import Foundation
import MarimoDomain
import MarimoProcess
import MarimoProtocol

public actor MarimoLSPAdapter: MarimoBackend {
  private let connection: JSONRPCConnection
  private let launchRequest: ProcessLaunchRequest
  private var backendStatus: BackendStatus = .unavailable

  public init(
    sidecarDirectory: URL,
    connection: JSONRPCConnection = JSONRPCConnection()
  ) throws {
    self.connection = connection
    launchRequest = try SidecarLaunchRequest.make(sidecarDirectory: sidecarDirectory)
  }

  public func status() async -> BackendStatus {
    guard await connection.currentState() == .ready else { return .unavailable }
    return backendStatus
  }

  public func start() async throws {
    if await connection.currentState() == .ready {
      backendStatus = .ready
      return
    }
    _ = try await connection.startAndInitialize(request: launchRequest)
    backendStatus = .ready
  }

  public func parseNotebook(source: String) async throws -> NotebookParseOutcome {
    guard backendStatus == .ready else { throw JSONRPCConnectionError.notInitialized }
    let command = MarimoCommand.parseNotebook(source: source)
    let params = try encodeAsJSONValue(command)
    let result = try await connection.request(method: "marimo/command", params: params)
    let parsed = try decode(ParseNotebookResult.self, from: result)
    switch parsed {
    case .success(let document):
      return .success(
        ParsedNotebook(
          cells: document.cells.map { cell in
            ParsedNotebookCell(
              sourceID: cell.id,
              code: cell.code ?? "",
              name: normalizedName(cell.name),
              configuration: CellConfiguration(
                column: cell.config.column,
                disabled: cell.config.disabled ?? false,
                hideCode: cell.config.hideCode ?? false
              )
            )
          }
        )
      )
    case .invalidSyntax(let line, let column):
      return .invalidSyntax(line: line, column: column)
    case .convertible:
      return .convertible
    }
  }

  public func shutdown() async {
    await connection.shutdown()
    backendStatus = .unavailable
  }

  private func normalizedName(_ name: String?) -> String {
    guard let name, !name.isEmpty else { return "_" }
    return name
  }

  private func encodeAsJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }

  private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
}
