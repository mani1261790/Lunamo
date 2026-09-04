import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoProcess
import Testing

@Suite("Bundled sidecar", .serialized)
struct BundledSidecarIntegrationTests {
  @Test("Initialize and bounded shutdown leave no sidecar process")
  func initializeAndShutdown() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let process = LSPProcess()
    let connection = JSONRPCConnection(transport: process)
    _ = try await connection.startAndInitialize(
      request: SidecarLaunchRequest.make(sidecarDirectory: sidecar)
    )
    #expect(await connection.currentState() == .ready)
    let clock = ContinuousClock()
    let shutdownStart = clock.now
    await connection.shutdown()
    // The request timeout is exactly five seconds; allow scheduler overhead around that bound.
    // MarimoLSPAdapter separately verifies the five-second whole-shutdown deadline.
    #expect(shutdownStart.duration(to: clock.now) < .seconds(6))
    let deadline = clock.now.advanced(by: .seconds(2))
    while await process.processIdentifier() != nil, clock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(await process.processIdentifier() == nil)
    #expect(await connection.pendingRequestCount() == 0)
  }

  @Test("Real adapter distinguishes two-cell, invalid, and convertible sources")
  func parseOutcomes() async throws {
    let root = repositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let source = try String(
      contentsOf: root.appending(path: "Tests/Fixtures/two_cell_notebook.py"),
      encoding: .utf8
    )
    let parsed = try await adapter.parseNotebook(source: source)
    guard case .success(let notebook) = parsed else {
      Issue.record("Two-cell fixture did not parse successfully")
      await adapter.shutdown()
      return
    }
    #expect(notebook.cells.count == 2)
    #expect(notebook.cells[0].code.contains("first = 20"))
    #expect(notebook.cells[1].code.contains("second = first + 22"))
    #expect(
      try await adapter.parseNotebook(source: "def broken(:\n")
        == .invalidSyntax(line: 1, column: 12)
    )
    #expect(try await adapter.parseNotebook(source: "print('hello')\n") == .convertible)
    await adapter.shutdown()
  }

  @Test("Real sidecar accepts notebook open, text, structure, save, and close synchronization")
  func notebookSynchronization() async throws {
    let sidecar = repositoryRoot().appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let documentID = UUID()
    let firstID = UUID()
    let first = syncCell(documentID: documentID, runtimeID: firstID, text: "value = 1")
    let uri = "untitled:MarimoNative-\(documentID.uuidString)"
    let snapshot = NotebookSyncSnapshot(
      uri: uri,
      version: 1,
      metadata: notebookMetadata,
      cells: [first]
    )
    try await adapter.didOpenNotebook(snapshot)
    try await adapter.didOpenNotebook(snapshot)
    try await adapter.didChangeNotebook(
      uri: uri,
      version: 2,
      change: .text(
        NotebookTextChange(
          cellURI: first.uri,
          version: 2,
          range: LSPRange(
            start: LSPPosition(line: 0, character: 9),
            end: LSPPosition(line: 0, character: 9)
          ),
          text: "0"
        )
      )
    )
    let second = syncCell(documentID: documentID, runtimeID: UUID(), text: "value")
    try await adapter.didChangeNotebook(
      uri: uri,
      version: 3,
      change: .structure(
        NotebookStructureChange(
          start: 1,
          deleteCount: 0,
          cells: [second],
          didOpen: [second]
        )
      )
    )
    try await adapter.didChangeNotebook(
      uri: uri,
      version: 4,
      change: .cellData([second])
    )
    try await adapter.didSaveNotebook(uri: uri)
    try await Task.sleep(for: .milliseconds(200))
    #expect(await adapter.status() == .ready)
    try await adapter.didCloseNotebook(uri: uri, cellURIs: [first.uri, second.uri])
    await adapter.shutdown()
  }

  @Test("Real sidecar lists packages from the exact selected environment")
  func packageListing() async throws {
    let sidecar = repositoryRoot().appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let packages = try await adapter.listPackages(
      notebookURI: "untitled:package-list",
      executable: sidecar.appending(path: "bin/python").path
    )
    #expect(packages.contains { $0.name == "marimo-base" && $0.version == "0.24.0" })
    #expect(packages == packages.sorted { $0.name < $1.name })
    await adapter.shutdown()
  }

  @Test("Official marimo fixture round-trips through native atomic save")
  func officialMarimoSaveRoundTrip() async throws {
    let root = repositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-official-roundtrip-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appending(path: "roundtrip.py")
    try FileManager.default.copyItem(
      at: root.appending(path: "Tests/Fixtures/two_cell_notebook.py"),
      to: target
    )

    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let store = await NotebookStore(backend: adapter)
    await store.startBackend()
    await store.open(target)
    let openedCells = await store.document.cells
    let firstCellID = try #require(openedCells.first?.runtimeID)
    await store.send(.updateCode(cellID: firstCellID, code: "first = 21"))
    #expect(try await store.save() == .saved(target))
    let isDirty = await store.document.dirty
    #expect(!isDirty)
    await store.close()
    await store.shutdownBackend()

    let verifier = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await verifier.start()
    let savedSource = try String(contentsOf: target, encoding: .utf8)
    guard case .success(let reparsed) = try await verifier.parseNotebook(source: savedSource) else {
      Issue.record("Official marimo could not parse the atomically saved source")
      await verifier.shutdown()
      return
    }
    #expect(reparsed.cells.count == 2)
    #expect(reparsed.cells[0].code == "first = 21")
    #expect(reparsed.cells[1].code.contains("second = first + 22"))
    await verifier.shutdown()
  }

  private var notebookMetadata: [String: JSONValue] {
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

  private func syncCell(documentID: UUID, runtimeID: UUID, text: String) -> NotebookSyncCell {
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

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
