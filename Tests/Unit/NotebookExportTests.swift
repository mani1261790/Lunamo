import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import Testing

private enum ExportEvent: Sendable, Equatable {
  case theme(NotebookDisplayTheme)
  case exported(NotebookExportFormat, String, Bool)
}

private actor ExportBackend: MarimoBackend {
  private var ready = false
  private var events: [ExportEvent] = []

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }
  func setDisplayTheme(_ theme: NotebookDisplayTheme) {
    events.append(.theme(theme))
  }
  func exportNotebook(
    notebookURI: String,
    format: NotebookExportFormat,
    includeCode: Bool
  ) -> String {
    events.append(.exported(format, notebookURI, includeCode))
    return "content-\(format.rawValue)"
  }
  func stderrLines() -> [String] {
    ["failure at \(FileManager.default.homeDirectoryForCurrentUser.path)/secret/project.py"]
  }
  func shutdown() { ready = false }
  func snapshot() -> [ExportEvent] { events }
}

@Suite("Notebook export", .serialized)
@MainActor
struct NotebookExportTests {
  @Test("Three export formats use the live sidecar and write exact returned bytes")
  func threeFormatsWriteExactBytes() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appending(path: "notebook.py")
    try Data().write(to: sourceURL)
    let backend = ExportBackend()
    let store = NotebookStore(
      backend: backend,
      document: NotebookDocumentState(
        sourceURL: sourceURL,
        cells: [NotebookCellState(code: "value = 42")],
        kernelSessionID: "live-session"
      )
    )
    await store.startBackend()

    for format in NotebookExportFormat.allCases {
      let destination = directory.appending(path: "result.\(format.filenameExtension)")
      try await store.exportNotebook(format: format, to: destination)
      #expect(try String(contentsOf: destination, encoding: .utf8) == "content-\(format.rawValue)")
    }
    #expect(
      await backend.snapshot().filter { if case .exported = $0 { true } else { false } }.count == 3)
  }

  @Test("Export requires a live session and theme synchronization is explicit")
  func liveSessionAndThemeGate() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = ExportBackend()
    let store = NotebookStore(backend: backend)
    await store.startBackend()
    #expect(!store.exportAllowed)
    await #expect(throws: NotebookExportError.liveSessionRequired) {
      try await store.exportNotebook(
        format: .html, to: directory.appending(path: "blocked.html"))
    }
    await store.setDisplayTheme(isDark: true)
    #expect(await backend.snapshot().contains(.theme(.dark)))
  }

  @Test("Log review redacts the home directory before the save action is available")
  func reviewableLogIsRedacted() async {
    let backend = ExportBackend()
    let store = NotebookStore(backend: backend)
    await store.startBackend()
    await store.prepareLogReview()
    #expect(store.backendLogsPresented)
    #expect(store.reviewableLogText.contains("~/secret/project.py"))
    #expect(!store.reviewableLogText.contains(FileManager.default.homeDirectoryForCurrentUser.path))
  }

  private func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
