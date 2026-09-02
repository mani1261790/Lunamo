import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

private actor KernelEventRecorder {
  private var values: [MarimoBackendEvent] = []
  private var started = false

  func markStarted() { started = true }
  func isStarted() -> Bool { started }
  func append(_ event: MarimoBackendEvent) { values.append(event) }
  func snapshot() -> [MarimoBackendEvent] { values }
}

extension BundledSidecarIntegrationTests {
  @Test("Required kernel fixtures are present and parse with the pinned sidecar")
  func requiredKernelFixturesParse() async throws {
    let root = kernelRepositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let parseable = [
      "two_cell_notebook.py", "slider_reactive.py", "stdout_stderr.py",
      "python_exception.py", "infinite_loop.py", "png_plot.py", "json_output.py",
      "csv_table.py", "html_output.py", "external_file_conflict.py",
      "missing_marimo_environment.py", "wrong_marimo_version.py", "kernel_crash.py",
    ]
    for name in parseable {
      let source = try String(
        contentsOf: root.appending(path: "Tests/Fixtures/\(name)"),
        encoding: .utf8
      )
      guard case .success = try await adapter.parseNotebook(source: source) else {
        Issue.record("Required fixture did not parse: \(name)")
        continue
      }
    }
    let syntaxError = try String(
      contentsOf: root.appending(path: "Tests/Fixtures/invalid_syntax.py"),
      encoding: .utf8
    )
    guard case .invalidSyntax = try await adapter.parseNotebook(source: syntaxError) else {
      Issue.record("Syntax-error fixture was not rejected")
      await adapter.shutdown()
      return
    }
    await adapter.shutdown()
  }

  @Test("NotebookStore reaches idle only after the real completed-run notification")
  @MainActor
  func storeSessionLifecycle() async throws {
    let root = kernelRepositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    let python = sidecar.appending(path: "bin/python")
    guard FileManager.default.isExecutableFile(atPath: python.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let first = NotebookCellState(code: "first = 20")
    let second = NotebookCellState(code: "second = first + 22")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let support = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-session-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: support) }
    let store = NotebookStore(
      backend: adapter,
      document: NotebookDocumentState(cells: [first, second]),
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support)
    )
    await store.startBackend()
    await store.choosePythonExecutable(python)
    store.chooseWorkingDirectory(root)
    await store.requestRunAll()
    #expect(store.executionTrustPromptPresented)
    store.authorizeRunOnce()

    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while store.document.kernelSessionID == nil || store.sessionState != .idle,
      ContinuousClock.now < deadline
    {
      try? await Task.sleep(for: .milliseconds(25))
    }
    #expect(store.document.kernelSessionID != nil)
    #expect(store.sessionState == .idle)
    #expect(store.document.cells[0].runtime.lastExecutedCode == "first = 20")
    #expect(store.document.cells[1].runtime.lastExecutedCode == "second = first + 22")
    await store.shutdownBackend()
  }

  @Test("Two-cell run delegates downstream reactive execution to marimo")
  func twoCellReactiveExecution() async throws {
    let root = kernelRepositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    let python = sidecar.appending(path: "bin/python")
    guard FileManager.default.isExecutableFile(atPath: python.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }

    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let source = try String(
      contentsOf: root.appending(path: "Tests/Fixtures/two_cell_notebook.py"),
      encoding: .utf8
    )
    guard case .success(let parsed) = try await adapter.parseNotebook(source: source) else {
      Issue.record("Two-cell fixture did not parse")
      await adapter.shutdown()
      return
    }
    let recorder = KernelEventRecorder()
    let stream = await adapter.backendEvents()
    let listener = Task {
      await recorder.markStarted()
      for await event in stream { await recorder.append(event) }
    }
    defer {
      listener.cancel()
      Task { await adapter.shutdown() }
    }
    while !(await recorder.isStarted()) { await Task.yield() }

    let documentID = UUID()
    let firstID = UUID()
    let secondID = UUID()
    let notebookURI = "untitled:MarimoNative-\(documentID.uuidString)"
    let first = kernelSyncCell(documentID: documentID, runtimeID: firstID, text: "first = 20")
    let second = kernelSyncCell(
      documentID: documentID,
      runtimeID: secondID,
      text: "second = first + 22\nsecond"
    )
    try await adapter.didOpenNotebook(
      NotebookSyncSnapshot(
        uri: notebookURI,
        version: 1,
        metadata: kernelNotebookMetadata,
        cells: [first, second]
      )
    )
    try await adapter.execute(
      notebookURI: notebookURI,
      executable: python.path,
      workingDirectory: root.path,
      cells: [
        NotebookExecutionCell(runtimeID: firstID, code: first.text),
        NotebookExecutionCell(runtimeID: secondID, code: second.text),
      ]
    )
    let initialCompleted = await waitForCompletedRun(
      in: recorder, notebookURI: notebookURI, after: 0)
    if !initialCompleted {
      Issue.record(
        "Initial execution events: \(await recorder.snapshot()); sessions: \(try await adapter.listSessions())"
      )
    }
    #expect(initialCompleted)
    let baseline = await recorder.snapshot().count

    try await adapter.didChangeNotebook(
      uri: notebookURI,
      version: 2,
      change: .text(
        NotebookTextChange(
          cellURI: first.uri,
          version: 2,
          range: nil,
          text: "first = 21"
        )
      )
    )
    try await adapter.execute(
      notebookURI: notebookURI,
      executable: python.path,
      workingDirectory: root.path,
      cells: [NotebookExecutionCell(runtimeID: firstID, code: "first = 21")]
    )
    #expect(await waitForCompletedRun(in: recorder, notebookURI: notebookURI, after: baseline))

    let reactiveEvents = Array((await recorder.snapshot()).dropFirst(baseline))
    let downstreamRan = reactiveEvents.contains { event in
      guard case .kernel(let kernel) = event,
        kernel.notebookURI == notebookURI,
        kernel.operation == "cell-op",
        case .string(secondID.uuidString)? = kernel.payload["cell_id"]
      else { return false }
      return true
    }
    if !downstreamRan { Issue.record("Reactive execution events: \(reactiveEvents)") }
    #expect(downstreamRan)
    #expect(
      reactiveEvents.contains { event in
        guard case .kernel(let kernel) = event else { return false }
        return kernel.notebookURI == notebookURI && kernel.operation == "completed-run"
      }
    )
    let printed = try await adapter.printNotebook(parsed.owned)
    #expect(printed.contains("first = 20"))
    #expect(printed.contains("second = first + 22"))
    await adapter.shutdown()
  }

  private func waitForCompletedRun(
    in recorder: KernelEventRecorder,
    notebookURI: String,
    after index: Int
  ) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while ContinuousClock.now < deadline {
      let events = await recorder.snapshot()
      if events.dropFirst(index).contains(where: { event in
        guard case .kernel(let kernel) = event else { return false }
        return kernel.notebookURI == notebookURI && kernel.operation == "completed-run"
      }) {
        return true
      }
      try? await Task.sleep(for: .milliseconds(25))
    }
    return false
  }

  private var kernelNotebookMetadata: [String: JSONValue] {
    [
      "marimo": .object([
        "appOptions": .object([
          "managed": .object(["autoDownload": .array([])]),
          "passthrough": .object([:]),
        ]),
        "header": .null,
        "notebookMetadata": .object([:]),
      ])
    ]
  }

  private func kernelSyncCell(
    documentID: UUID, runtimeID: UUID, text: String
  ) -> NotebookSyncCell {
    NotebookSyncCell(
      runtimeID: runtimeID,
      uri: "marimo-native-notebook-cell://\(documentID.uuidString)/\(runtimeID.uuidString)",
      version: 1,
      text: text,
      metadata: [
        "marimo": .object([
          "name": .string("_"),
          "options": .object([
            "column": .null,
            "disabled": .bool(false),
            "hide_code": .bool(false),
          ]),
          "sourceProjections": .object(["markdown": .null, "sql": .null]),
        ]),
        "marimoRuntime": .object([
          "stableId": .string(runtimeID.uuidString),
          "state": .null,
        ]),
      ]
    )
  }

  private func kernelRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
