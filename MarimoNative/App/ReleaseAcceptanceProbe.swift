import AppKit
import Foundation
import MarimoApplication
import MarimoDomain
import MarimoEnvironment

@MainActor
enum ReleaseAcceptanceProbe {
  private static var started = false

  static func run(store: NotebookStore) async {
    guard !started, CommandLine.arguments.contains("--release-acceptance-marker") else { return }
    started = true
    guard let configuration = configuration() else {
      if let rawMarker = argument(after: "--release-acceptance-marker") {
        let marker = canonicalizedParentURL(rawMarker)
        let rawNotebook = argument(after: "--release-acceptance-notebook") ?? "missing"
        let rawPython = argument(after: "--release-acceptance-python") ?? "missing"
        try? writeResult(
          [
            "status": "failed",
            "error": "invalid release acceptance arguments",
            "notebook": URL(fileURLWithPath: rawNotebook).resolvingSymlinksInPath().path,
            "python": URL(fileURLWithPath: rawPython).standardizedFileURL.path,
            "marker": marker.path,
            "temporaryRoot": FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path,
            "bundle": Bundle.main.bundlePath,
          ],
          to: marker
        )
      }
      NSApplication.shared.terminate(nil)
      return
    }
    do {
      try await waitFor("notebook open") {
        store.openState == .loaded(configuration.notebook)
          && store.backendStatus == .ready
          && store.document.cells.count == 2
      }
      guard let firstCell = store.document.cells.first else {
        throw ProbeError.failed("opened notebook contains no cells")
      }

      await store.choosePythonExecutable(configuration.python)
      guard case .ready(let details, _) = store.environmentState,
        details.executableURL.standardizedFileURL == configuration.python.standardizedFileURL
      else {
        throw ProbeError.failed("selected Python environment did not pass preflight")
      }

      await store.send(.updateCode(cellID: firstCell.runtimeID, code: "first = 21"))
      guard store.document.dirty else {
        throw ProbeError.failed("native edit did not mark the document dirty")
      }
      guard try await store.save() == .saved(configuration.notebook) else {
        throw ProbeError.failed("native save did not write the opened notebook")
      }
      let saved = try String(contentsOf: configuration.notebook, encoding: .utf8)
      guard saved.contains("first = 21") else {
        throw ProbeError.failed("saved marimo source does not contain the native edit")
      }

      await store.requestRunAll()
      try await waitFor("execution trust prompt") { store.executionTrustPromptPresented }
      store.authorizeRunOnce()
      try await waitFor("sample execution", timeout: .seconds(30)) {
        store.sessionState == .idle
          && store.document.kernelSessionID != nil
          && outputContains("43", in: store.document.cells.last?.runtime.output)
      }

      await store.close()
      await store.shutdownBackend()
      try writeResult(
        [
          "status": "passed",
          "open": true,
          "edit": true,
          "save": true,
          "pythonSelection": true,
          "trustPrompt": true,
          "execute": true,
          "output": "43",
          "cleanup": store.sessionState == .closed,
        ],
        to: configuration.marker
      )
    } catch {
      let failure: [String: Any] = [
        "status": "failed",
        "error": String(describing: error),
        "backendStatus": String(describing: store.backendStatus),
        "sessionState": store.sessionStatusLabel,
        "kernelSession": store.document.kernelSessionID ?? "none",
        "outputs": store.document.cells.map { String(describing: $0.runtime.output) },
        "synchronizationError": store.synchronizationError ?? "none",
        "saveMessage": store.saveMessage ?? "none",
      ]
      await store.shutdownBackend()
      try? writeResult(failure, to: configuration.marker)
    }
    NSApplication.shared.terminate(nil)
  }

  private static func waitFor(
    _ operation: String,
    timeout: Duration = .seconds(60),
    condition: () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    guard condition() else { throw ProbeError.timedOut(operation) }
  }

  private static func outputContains(_ expected: String, in output: MarimoOutput?) -> Bool {
    guard let output, case .string(let value) = output.data else { return false }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == expected || trimmed.contains(">\(expected)<")
  }

  private static func writeResult(_ result: [String: Any], to marker: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    try data.write(to: marker, options: .withoutOverwriting)
  }

  private static func configuration() -> Configuration? {
    guard
      let notebook = argument(after: "--release-acceptance-notebook"),
      let python = argument(after: "--release-acceptance-python"),
      let marker = argument(after: "--release-acceptance-marker")
    else { return nil }
    let configuration = Configuration(
      notebook: canonicalizedParentURL(notebook),
      python: URL(fileURLWithPath: python).standardizedFileURL,
      marker: canonicalizedParentURL(marker)
    )
    let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"
    guard configuration.notebook.path.hasPrefix(temporaryRoot),
      configuration.marker.path.hasPrefix(temporaryRoot),
      configuration.python.isFileURL,
      configuration.python.path.hasPrefix(Bundle.main.bundlePath + "/")
    else { return nil }
    return configuration
  }

  private static func argument(after flag: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static func canonicalizedParentURL(_ path: String) -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    return url.deletingLastPathComponent().resolvingSymlinksInPath()
      .appending(path: url.lastPathComponent)
  }

  private struct Configuration {
    let notebook: URL
    let python: URL
    let marker: URL
  }

  private enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    case timedOut(String)

    var description: String {
      switch self {
      case .failed(let reason): reason
      case .timedOut(let operation): "timed out waiting for \(operation)"
      }
    }
  }
}
