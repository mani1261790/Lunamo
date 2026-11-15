import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import MarimoOutput
import Testing

extension BundledSidecarIntegrationTests {
  @Test("Real Python failures preserve edits and allow a successful rerun in the same session")
  @MainActor
  func pythonFailureRecoveryMatrix() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sidecar = root.appending(path: ".build/Sidecar")
    let support = FileManager.default.temporaryDirectory.appending(
      path: "lunamo-error-matrix-\(UUID())")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let cell = NotebookCellState(code: "1 + 1")
    let store = NotebookStore(
      backend: adapter, document: NotebookDocumentState(cells: [cell]),
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support),
      sessionResolutionTimeout: .seconds(5)
    )
    do {
      await store.startBackend()
      await store.choosePythonExecutable(sidecar.appending(path: "bin/python"))
      store.chooseWorkingDirectory(support)
      let sources = [
        "if True print('invalid')", "lunamo_undefined_name", "1 / 0",
        "import lunamo_nonexistent_dependency_93d1",
        "raise ValueError('日本語の検証エラー')",
      ]
      for source in sources {
        await store.send(.updateCode(cellID: cell.runtimeID, code: source))
        await store.requestRunCell(cell.runtimeID)
        store.authorizeRunOnce()
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
          if store.sessionState == .idle && store.document.cells[0].runtime.hasExecutionError {
            break
          }
          try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.sessionState == .idle, "Failure did not finish: \(source)")
        #expect(store.document.cells[0].runtime.hasExecutionError, "Missing error: \(source)")
        #expect(!store.document.cells[0].runtime.successfullyExecuted(source))
        #expect(store.document.cells[0].code == source)
        #expect(store.document.dirty)
        let isMissingPackageFailure = source.hasPrefix("import lunamo_nonexistent_dependency")
        if isMissingPackageFailure {
          let packageAlertDeadline = ContinuousClock.now.advanced(by: .seconds(5))
          while store.missingPackages.isEmpty, ContinuousClock.now < packageAlertDeadline {
            try await Task.sleep(for: .milliseconds(25))
          }
          #expect(store.missingPackages == ["lunamo-nonexistent-dependency-93d1"])
        }
        let session = store.document.kernelSessionID
        await store.send(.updateCode(cellID: cell.runtimeID, code: "40 + 2"))
        await store.requestRunCell(cell.runtimeID)
        store.authorizeRunOnce()
        let recoveryDeadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < recoveryDeadline {
          if store.sessionState == .idle
            && store.document.cells[0].runtime.successfullyExecuted("40 + 2")
          {
            break
          }
          try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.document.cells[0].runtime.successfullyExecuted("40 + 2"))
        #expect(store.document.kernelSessionID == session)
        if isMissingPackageFailure {
          #expect(store.missingPackages.isEmpty)
        }
      }
      await store.shutdownBackend()
    } catch {
      await store.shutdownBackend()
      throw error
    }
  }
  @Test("Run All isolates an error to its dependency branch regardless of display order")
  @MainActor
  func runAllDependencyFailureRecovery() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let support = FileManager.default.temporaryDirectory.appending(
      path: "lunamo-branches-\(UUID())")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let sidecar = root.appending(path: ".build/Sidecar")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    // The dependent is deliberately above its failed ancestor in display order.
    let cells = [
      NotebookCellState(code: "downstream = upstream + 1\ndownstream"),
      NotebookCellState(code: "upstream = 1 / 0"),
      NotebookCellState(code: "independent = 42\nindependent"),
    ]
    let store = NotebookStore(
      backend: adapter, document: NotebookDocumentState(cells: cells),
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support))
    do {
      await store.startBackend()
      await store.choosePythonExecutable(sidecar.appending(path: "bin/python"))
      store.chooseWorkingDirectory(support)
      await store.requestRunAll()
      store.authorizeRunOnce()
      let deadline = ContinuousClock.now.advanced(by: .seconds(20))
      while ContinuousClock.now < deadline {
        if store.sessionState == .idle && store.document.cells[1].runtime.hasExecutionError {
          break
        }
        try await Task.sleep(for: .milliseconds(25))
      }
      #expect(store.sessionState == .idle)
      #expect(store.document.cells[1].runtime.hasExecutionError)
      #expect(!store.document.cells[0].runtime.successfullyExecuted(cells[0].code))
      #expect(store.document.cells[2].runtime.successfullyExecuted(cells[2].code))
      #expect(recoveryOutputText(store.document.cells[2].runtime.output) == "42")
      await store.send(.updateCode(cellID: cells[1].runtimeID, code: "upstream = 40"))
      await store.requestRunCell(cells[1].runtimeID)
      store.authorizeRunOnce()
      let recoveryDeadline = ContinuousClock.now.advanced(by: .seconds(20))
      while ContinuousClock.now < recoveryDeadline {
        if store.sessionState == .idle && !store.document.cells[0].runtime.hasExecutionError
          && !store.document.cells[1].runtime.hasExecutionError
          && recoveryOutputText(store.document.cells[0].runtime.output) == "41"
        {
          break
        }
        try await Task.sleep(for: .milliseconds(25))
      }
      #expect(store.sessionState == .idle)
      #expect(!store.document.cells[0].runtime.hasExecutionError)
      #expect(store.document.cells[0].runtime.status == .idle)
      #expect(recoveryOutputText(store.document.cells[0].runtime.output) == "41")
      #expect(store.document.cells[2].runtime.successfullyExecuted(cells[2].code))
      await store.shutdownBackend()
    } catch {
      await store.shutdownBackend()
      throw error
    }
  }

  @Test("A terminated Python kernel can be restarted without losing or reexecuting edited source")
  @MainActor
  func abruptKernelExitRecovery() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let support = FileManager.default.temporaryDirectory.appending(
      path: "lunamo-kernel-exit-\(UUID())")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let sidecar = root.appending(path: ".build/Sidecar")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let cell = NotebookCellState(
      code:
        "from pathlib import Path\nimport os\nPath('exit-reached').write_text('ready')\nos._exit(17)"
    )
    let store = NotebookStore(
      backend: adapter, document: NotebookDocumentState(cells: [cell]),
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support),
      sessionResolutionTimeout: .seconds(3), interruptTimeout: .seconds(1))
    do {
      await store.startBackend()
      await store.choosePythonExecutable(sidecar.appending(path: "bin/python"))
      store.chooseWorkingDirectory(support)
      await store.requestRunCell(cell.runtimeID)
      store.authorizeRunOnce()
      let marker = support.appending(path: "exit-reached")
      let deadline = ContinuousClock.now.advanced(by: .seconds(15))
      while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
      }
      try #require(FileManager.default.fileExists(atPath: marker.path))
      // The marker is written by Python before its lifecycle notifications reach Swift.
      let notificationDeadline = ContinuousClock.now.advanced(by: .seconds(5))
      while !store.sessionAllowsRestart, ContinuousClock.now < notificationDeadline {
        try await Task.sleep(for: .milliseconds(25))
      }
      await store.send(.updateCode(cellID: cell.runtimeID, code: "recovered = 42\nrecovered"))
      #expect(store.document.dirty)
      try #require(store.sessionAllowsRestart)
      await store.requestRestartKernel()
      let restartDeadline = ContinuousClock.now.advanced(by: .seconds(15))
      while store.sessionState != .idle, ContinuousClock.now < restartDeadline {
        try await Task.sleep(for: .milliseconds(25))
      }
      try #require(store.sessionState == .idle)
      #expect(store.document.cells[0].code == "recovered = 42\nrecovered")
      #expect(store.document.cells[0].runtime.lastExecutedCode == nil)
      await store.requestRunCell(cell.runtimeID)
      store.authorizeRunOnce()
      let runDeadline = ContinuousClock.now.advanced(by: .seconds(15))
      while !store.document.cells[0].runtime.successfullyExecuted("recovered = 42\nrecovered"),
        ContinuousClock.now < runDeadline
      {
        try await Task.sleep(for: .milliseconds(25))
      }
      try #require(
        store.document.cells[0].runtime.successfullyExecuted("recovered = 42\nrecovered"))
      let saved = support.appending(path: "recovered.py")
      _ = try await store.saveAs(to: saved)
      await store.open(saved)
      #expect(store.document.cells[0].code == "recovered = 42\nrecovered")
      #expect(!store.document.dirty)
      await store.shutdownBackend()
    } catch {
      await store.shutdownBackend()
      throw error
    }
  }

  @Test("Creating a missing recovery session does not execute notebook code")
  @MainActor
  func missingRecoverySessionDoesNotExecute() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sidecar = root.appending(path: ".build/Sidecar")
    let support = FileManager.default.temporaryDirectory.appending(
      path: "lunamo-missing-session-\(UUID())")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let cell = NotebookCellState(
      code: "from pathlib import Path\nPath('executed').write_text('yes')\n42")
    let store = NotebookStore(
      backend: adapter, document: NotebookDocumentState(cells: [cell]),
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support))
    do {
      await store.startBackend()
      await store.choosePythonExecutable(sidecar.appending(path: "bin/python"))
      store.chooseWorkingDirectory(support)
      try await adapter.restartSession(
        notebookURI: store.document.notebookURI,
        executable: sidecar.appending(path: "bin/python").path,
        workingDirectory: support.path, createIfMissing: true)
      let sessions = try await adapter.listSessions()
      try #require(sessions.contains { $0.notebookURI == store.document.notebookURI })
      #expect(
        try await adapter.readNotebookOutputs(notebookURI: store.document.notebookURI).isEmpty)
      #expect(store.document.cells[0].runtime.lastExecutedCode == nil)
      #expect(!FileManager.default.fileExists(atPath: support.appending(path: "executed").path))
      await store.requestRunCell(cell.runtimeID)
      store.authorizeRunOnce()
      let runDeadline = ContinuousClock.now.advanced(by: .seconds(15))
      while recoveryOutputText(store.document.cells[0].runtime.output) != "42",
        ContinuousClock.now < runDeadline
      {
        try await Task.sleep(for: .milliseconds(25))
      }
      #expect(recoveryOutputText(store.document.cells[0].runtime.output) == "42")
      #expect(FileManager.default.fileExists(atPath: support.appending(path: "executed").path))
      await store.shutdownBackend()
    } catch {
      await store.shutdownBackend()
      throw error
    }
  }

  private func recoveryOutputText(_ output: MarimoOutput?) -> String? {
    guard let output, case .string(let source) = output.data else { return nil }
    if output.mimeType == "text/html" { return HTMLNativeSubsetDecoder.decode(source) }
    return source
  }

}
