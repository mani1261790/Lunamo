import Foundation
import MarimoDomain

extension NotebookStore {
  /// Allowlisted metadata only. Never interpolate error bodies, paths, source or output.
  public var diagnosticSummary: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    let os = ProcessInfo.processInfo.operatingSystemVersion
    let phase: String
    switch sessionState {
    case .notStarted: phase = "not-started"
    case .starting: phase = "starting"
    case .idle: phase = "idle"
    case .running: phase = "running"
    case .interrupting: phase = "interrupting"
    case .restarting: phase = "restarting"
    case .failed: phase = "failed"
    case .closed: phase = "closed"
    }
    let lines = [
      "Lunamo diagnostic summary (no automatic upload)",
      "App: \(version) (\(build))",
      "macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      "Python: \(selectedPythonEnvironment?.pythonVersion.description ?? "not-selected")",
      "Backend: \(backendStatus == .ready ? "ready" : "unavailable")",
      "Session state: \(phase)",
      "Cells: \(document.cells.count)",
      "Cells with execution errors: \(document.cells.filter { $0.runtime.hasExecutionError }.count)",
      "Document has unsaved changes: \(document.dirty)",
      "",
      "Excluded: notebook name/path, session ID, code, outputs, variables, environment variables, stderr.",
    ]
    return lines.joined(separator: "\n")
  }

  public func saveReviewedDiagnostics(_ text: String, to destination: URL) throws {
    try Data(text.utf8).write(to: destination, options: .atomic)
  }
}
