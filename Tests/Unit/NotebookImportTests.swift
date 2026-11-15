import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import Testing

private actor ImportBackend: MarimoBackend {
  let convertedSource: String
  let convertedParseOutcome: NotebookParseOutcome
  var conversions: [(String, NotebookImportSourceFormat)] = []
  var isStarted = false

  init(
    convertedSource: String = "converted marimo source",
    convertedParseOutcome: NotebookParseOutcome = .success(
      ParsedNotebook(
        cells: [
          ParsedNotebookCell(
            sourceID: "imported",
            code: "answer = 42",
            name: "_",
            configuration: CellConfiguration()
          )
        ]
      )
    )
  ) {
    self.convertedSource = convertedSource
    self.convertedParseOutcome = convertedParseOutcome
  }

  func status() -> BackendStatus { isStarted ? .ready : .unavailable }
  func start() { isStarted = true }

  func parseNotebook(source: String) -> NotebookParseOutcome {
    source == convertedSource
      ? convertedParseOutcome
      : .success(
        ParsedNotebook(
          cells: [
            ParsedNotebookCell(
              sourceID: "saved",
              code: "answer = 42",
              name: "_",
              configuration: CellConfiguration()
            )
          ]
        )
      )
  }

  func convertNotebook(source: String, format: NotebookImportSourceFormat) -> String {
    conversions.append((source, format))
    return convertedSource
  }

  func shutdown() { isStarted = false }
}

@Suite("Notebook import", .serialized)
@MainActor
struct NotebookImportTests {
  @Test("Jupyter import prepares a separate Python destination")
  func preparesJupyterImport() async throws {
    let sourceURL = try temporaryFile(name: "lesson.ipynb", source: #"{"cells":[]}"#)
    defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
    let backend = ImportBackend()
    let store = NotebookStore(backend: backend)

    let draft = try await store.prepareImport(from: sourceURL)

    #expect(draft.sourceURL == sourceURL)
    #expect(draft.suggestedFilename == "lesson.py")
    #expect(draft.convertedSource == "converted marimo source")
    let conversions = await backend.conversions
    #expect(conversions.count == 1)
    #expect(conversions.first?.0 == #"{"cells":[]}"#)
    #expect(conversions.first?.1 == .ipynb)
    #expect(store.openState == .idle)
  }

  @Test("Regular Python import defaults to a non-conflicting filename")
  func preparesPythonImport() async throws {
    let sourceURL = try temporaryFile(name: "analysis.py", source: "print('hello')\n")
    defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
    let backend = ImportBackend()
    let store = NotebookStore(backend: backend)

    let draft = try await store.prepareImport(from: sourceURL)

    #expect(draft.suggestedFilename == "analysis_marimo.py")
    #expect(await backend.conversions.first?.1 == .python)
  }

  @Test("Jupyter package cells become an explicit import requirement")
  func preservesConvertedDependencies() async throws {
    let sourceURL = try temporaryFile(name: "keras.ipynb", source: #"{"cells":[]}"#)
    defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
    let converted = """
      # /// script
      # dependencies = ["keras", "numpy>=2"]
      # ///
      import marimo
      """
    let store = NotebookStore(backend: ImportBackend(convertedSource: converted))

    let draft = try await store.prepareImport(from: sourceURL)

    #expect(draft.requiredPackages == ["keras", "numpy>=2"])
  }

  @Test("Import never replaces its source file")
  func rejectsSourceDestination() async throws {
    let source = "print('keep me')\n"
    let sourceURL = try temporaryFile(name: "source.py", source: source)
    defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
    let store = NotebookStore(backend: ImportBackend())
    let draft = try await store.prepareImport(from: sourceURL)

    await #expect(throws: NotebookImportError.sourceAndDestinationMatch) {
      try await store.saveImportedNotebook(draft, to: sourceURL)
    }
    #expect(try String(contentsOf: sourceURL, encoding: .utf8) == source)
  }

  @Test("Saved conversion opens as the active marimo notebook")
  func savesAndOpensConversion() async throws {
    let sourceURL = try temporaryFile(name: "lesson.ipynb", source: #"{"cells":[]}"#)
    let directory = sourceURL.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = NotebookStore(backend: ImportBackend())
    let draft = try await store.prepareImport(from: sourceURL)
    let destination = directory.appending(path: "lesson.py")

    try await store.saveImportedNotebook(draft, to: destination)

    #expect(try String(contentsOf: destination, encoding: .utf8) == draft.convertedSource)
    #expect(store.openState == .loaded(destination))
    #expect(store.document.sourceURL == destination)
  }

  @Test("Invalid converter output is not offered for saving")
  func rejectsInvalidConvertedNotebook() async throws {
    let sourceURL = try temporaryFile(name: "broken.ipynb", source: "{}")
    defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
    let backend = ImportBackend(convertedParseOutcome: .convertible)
    let store = NotebookStore(backend: backend)

    await #expect(throws: NotebookImportError.invalidConvertedNotebook) {
      try await store.prepareImport(from: sourceURL)
    }
    guard case .failed(let failedURL, _) = store.openState else {
      Issue.record("Expected failed import state")
      return
    }
    #expect(failedURL == sourceURL)
    #expect(store.userFacingError?.code == .documentConvert)
  }

  private func temporaryFile(name: String, source: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-import-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appending(path: name)
    try Data(source.utf8).write(to: url)
    return url
  }
}
