import MarimoDomain
import MarimoProtocol

extension MarimoLSPAdapter {
  public func setDisplayTheme(_ theme: NotebookDisplayTheme) async throws {
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(
        MarimoCommand.setDisplayTheme(theme == .dark ? .dark : .light)
      )
    )
  }

  public func exportNotebook(
    notebookURI: String,
    format: NotebookExportFormat,
    includeCode: Bool
  ) async throws -> String {
    let command: MarimoCommand
    switch format {
    case .html:
      command = .exportHTML(
        ExportHTMLCommand(
          notebookURI: notebookURI,
          download: false,
          files: [],
          includeCode: includeCode
        )
      )
    case .ipynb:
      command = .exportIPYNB(NotebookURICommand(notebookURI: notebookURI))
    case .markdown:
      command = .exportMarkdown(NotebookURICommand(notebookURI: notebookURI))
    }
    let result = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(command)
    )
    guard case .string(let content) = result else {
      throw JSONRPCConnectionError.protocolFailure
    }
    return content
  }

  public func stderrLines() async -> [String] {
    await connection.stderrLines()
  }
}
