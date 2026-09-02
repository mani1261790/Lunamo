import MarimoProtocol

extension MarimoLSPAdapter {
  public func interrupt(notebookURI: String, kernelSessionID: String) async throws {
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(
        MarimoCommand.interrupt(
          InterruptCommand(notebookURI: notebookURI, kernelSessionID: kernelSessionID)
        )
      )
    )
  }

  public func restartSession(
    notebookURI: String,
    executable: String,
    workingDirectory: String,
    createIfMissing: Bool
  ) async throws {
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(
        MarimoCommand.restartSession(
          RestartSessionCommand(
            notebookURI: notebookURI,
            executable: executable,
            workingDirectory: workingDirectory,
            createIfMissing: createIfMissing
          )
        )
      )
    )
  }

  public func sendStdin(
    notebookURI: String,
    kernelSessionID: String,
    text: String
  ) async throws {
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(
        MarimoCommand.sendStdin(
          SendStdinCommand(
            notebookURI: notebookURI,
            kernelSessionID: kernelSessionID,
            text: text
          )
        )
      )
    )
  }
}
