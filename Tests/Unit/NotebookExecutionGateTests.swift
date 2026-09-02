import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

private actor ExecutionGateBackend: MarimoBackend {
  private var ready = false
  private var executions = 0

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome {
    .success(
      ParsedNotebook(
        cells: [
          ParsedNotebookCell(
            sourceID: "cell", code: "value = 1", name: "_", configuration: CellConfiguration()
          )
        ]
      )
    )
  }
  func execute(
    notebookURI _: String,
    executable _: String,
    workingDirectory _: String,
    cells _: [NotebookExecutionCell]
  ) {
    executions += 1
  }
  func shutdown() { ready = false }
  func executionCount() -> Int { executions }
}

@Suite("Notebook execution gate", .serialized)
@MainActor
struct NotebookExecutionGateTests {
  @Test("Execution requires valid preflight and consumes Run Once authorization")
  func preflightAndTrustGate() async {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executable)
    let backend = ExecutionGateBackend()
    let store = NotebookStore(backend: backend, environmentPreflight: preflight)
    let cellID = store.document.cells[0].runtimeID
    let canonicalExecutable = normalizedExecutableURL(executable).path
    let workingDirectory = canonicalURL(URL(fileURLWithPath: "/tmp")).path
    await store.startBackend()

    await store.send(
      .runCell(
        cellID: cellID, executable: canonicalExecutable, workingDirectory: workingDirectory
      )
    )
    #expect(await backend.executionCount() == 0)

    await store.choosePythonExecutable(executable)
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/tmp"))
    await store.send(
      .runCell(
        cellID: cellID, executable: canonicalExecutable, workingDirectory: workingDirectory
      )
    )
    #expect(await backend.executionCount() == 0)

    store.authorizeRunOnce()
    await store.send(
      .runCell(
        cellID: cellID, executable: canonicalExecutable, workingDirectory: workingDirectory
      )
    )
    #expect(await backend.executionCount() == 1)
    await store.send(
      .runCell(
        cellID: cellID, executable: canonicalExecutable, workingDirectory: workingDirectory
      )
    )
    #expect(await backend.executionCount() == 1)
  }

  @Test("Untitled documents require an existing absolute working directory")
  func untitledWorkingDirectory() async {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executable)
    let store = NotebookStore(backend: ExecutionGateBackend(), environmentPreflight: preflight)
    await store.choosePythonExecutable(executable)
    guard case .needsWorkingDirectory = store.environmentState else {
      Issue.record("Untitled document did not request a working directory")
      return
    }
    guard let relativeDirectory = URL(string: "relative") else {
      Issue.record("Could not construct relative URL fixture")
      return
    }
    store.chooseWorkingDirectory(relativeDirectory)
    guard case .needsWorkingDirectory = store.environmentState else {
      Issue.record("Relative working directory was accepted")
      return
    }
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/path/that/does/not/exist"))
    guard case .needsWorkingDirectory = store.environmentState else {
      Issue.record("Missing working directory was accepted")
      return
    }
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/tmp"))
    guard case .ready = store.environmentState else {
      Issue.record("Existing absolute working directory was rejected")
      return
    }
  }

  @Test("Opening a notebook configures preflight without prompting for execution trust")
  func openDoesNotPromptOrExecute() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-open-trust-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: ".git"), withIntermediateDirectories: true
    )
    let executable = root.appending(path: ".venv/bin/python")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: executable, withDestinationURL: URL(fileURLWithPath: "/bin/sh"))
    let notebook = root.appending(path: "notebook.py")
    try Data("source".utf8).write(to: notebook)
    let support = root.appending(path: "support")
    let selectionStore = WorkspaceEnvironmentStore(applicationSupportDirectory: support)
    let discovery = PythonEnvironmentDiscovery(store: selectionStore)
    let trust = FolderTrustStore(applicationSupportDirectory: support)
    let (preflight, transport) = successfulPreflight(
      executableURL: URL(fileURLWithPath: "/bin/sh")
    )
    let backend = ExecutionGateBackend()
    let store = NotebookStore(
      backend: backend,
      environmentDiscovery: discovery,
      environmentPreflight: preflight,
      folderTrustStore: trust
    )

    await store.open(notebook)

    #expect(store.openState == .loaded(notebook))
    #expect(!store.executionTrustPromptPresented)
    #expect(await backend.executionCount() == 0)
    #expect(await transport.recordedRequests().isEmpty)
    guard case .selected = store.environmentState else {
      Issue.record("Opening did more than select the discovered environment candidate")
      return
    }
  }
}
