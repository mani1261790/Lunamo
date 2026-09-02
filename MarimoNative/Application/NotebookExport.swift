import Foundation
import MarimoBackend
import MarimoDomain

extension NotebookStore {
  public var exportAllowed: Bool {
    backendStatus == .ready && document.kernelSessionID != nil && document.sourceURL != nil
  }

  public func setDisplayTheme(isDark: Bool) async {
    guard backendStatus == .ready else { return }
    do {
      try await backend.setDisplayTheme(isDark ? .dark : .light)
    } catch {
      presentError(
        code: .lspProtocol,
        cause: "The output theme could not be synchronized: \(error.localizedDescription)",
        target: document.kernelSessionID ?? document.notebookURI,
        recoveryActions: ["Retry", "Continue with the current output theme"]
      )
    }
  }

  public func exportNotebook(
    format: NotebookExportFormat,
    to destination: URL,
    includeCode: Bool = true
  ) async throws {
    guard exportAllowed else { throw NotebookExportError.liveSessionRequired }
    try await flushCommittedTextChanges()
    let content = try await backend.exportNotebook(
      notebookURI: document.notebookURI,
      format: format,
      includeCode: includeCode
    )
    try Data(content.utf8).write(to: destination, options: .atomic)
    MarimoLog.document.info(
      "Exported \(format.rawValue, privacy: .public) to \(MarimoLogPrivacy.redactHomePrefix(in: destination.path), privacy: .public)"
    )
  }

  public func prepareLogReview() async {
    backendLogs = await backend.stderrLines()
    backendLogsPresented = true
  }

  public var reviewableLogText: String {
    let header = [
      "MarimoNative diagnostic log",
      "Generated: \(Date().ISO8601Format())",
      "Notebook: \(MarimoLogPrivacy.redactHomePrefix(in: document.sourceURL?.path ?? "Untitled"))",
      "Session: \(document.kernelSessionID ?? "Not Started")",
      "",
      "Sidecar stderr (bounded to 200 lines):",
    ]
    let redacted = backendLogs.map { MarimoLogPrivacy.redactHomePrefix(in: $0) }
    return (header + (redacted.isEmpty ? ["No sidecar stderr was captured."] : redacted))
      .joined(separator: "\n")
  }

  public func reportExportFailure(_ error: any Error, destination: URL) {
    presentError(
      code: .documentSave,
      cause: "Export failed: \(error.localizedDescription)",
      target: MarimoLogPrivacy.redactHomePrefix(in: destination.path),
      recoveryActions: ["Retry Export", "Choose Another Location"]
    )
  }
}

public enum NotebookExportError: LocalizedError, Sendable, Equatable {
  case liveSessionRequired

  public var errorDescription: String? {
    switch self {
    case .liveSessionRequired:
      "Run the notebook before exporting so the live session can produce the file."
    }
  }
}
