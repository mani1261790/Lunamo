import Foundation
import MarimoBackend
import MarimoDomain
import MarimoProcess
import MarimoProtocol
import Testing

private actor MockProcessTransport: ProcessTransport {
  private var continuation: AsyncStream<ProcessEvent>.Continuation?
  private var messages: [JSONRPCMessage] = []
  private var running = false
  private var framer = JSONRPCFramer()
  var methodsWithoutAutomaticResponse: Set<String> = []
  private var writeDelays: [String: Duration] = [:]
  private var startCount = 0

  func start(_: ProcessLaunchRequest) -> AsyncStream<ProcessEvent> {
    running = true
    startCount += 1
    let (stream, continuation) = AsyncStream<ProcessEvent>.makeStream()
    self.continuation = continuation
    return stream
  }

  func write(_ data: Data) async throws {
    for payload in try framer.append(data) {
      let message = try JSONDecoder().decode(JSONRPCMessage.self, from: payload)
      let method: String?
      switch message {
      case .request(_, let value, _), .notification(let value, _): method = value
      default: method = nil
      }
      if let method, let delay = writeDelays[method] {
        try await Task.sleep(for: delay)
      }
      messages.append(message)
      if case .notification("exit", _) = message {
        terminate()
        continue
      }
      if case .request(let id, let method, let params) = message,
        !methodsWithoutAutomaticResponse.contains(method)
      {
        let result: JSONValue
        if method == "initialize" {
          result = .object([
            "serverInfo": .object(["name": .string("mock")]),
            "capabilities": .object(["notebookDocumentSync": .bool(true)]),
          ])
        } else if method == "marimo/command",
          params?.object?["kind"] == .string("print-notebook")
        {
          result = .object(["source": .string("# printed exactly\r\n")])
        } else {
          result = .object(["method": .string(method)])
        }
        try emit(.response(id: id, result: result))
      }
    }
  }

  func terminate() {
    guard running else { return }
    running = false
    continuation?.yield(.terminated(15))
    continuation?.finish()
  }

  func processIdentifier() -> Int32? { running ? 42 : nil }

  func snapshot() -> [JSONRPCMessage] { messages }
  func recordedStartCount() -> Int { startCount }

  func disableAutomaticResponse(for method: String) {
    methodsWithoutAutomaticResponse.insert(method)
  }

  func delayWrite(for method: String, by duration: Duration) {
    writeDelays[method] = duration
  }

  func emit(_ message: JSONRPCMessage) throws {
    let payload = try JSONEncoder().encode(message)
    continuation?.yield(.stdout(try JSONRPCFramer.frame(payload)))
  }

  func emitRaw(_ data: Data) { continuation?.yield(.stdout(data)) }

  func emitStderr(_ text: String) { continuation?.yield(.stderr(Data(text.utf8))) }
}

@Suite("JSON-RPC connection")
struct JSONRPCConnectionTests {
  @Test("Initialize precedes initialized and captures server information")
  func initializeHandshake() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let record = try await connection.startAndInitialize(request: launchRequest())
    #expect(record.serverInfo == .object(["name": .string("mock")]))
    #expect(record.capabilities == .object(["notebookDocumentSync": .bool(true)]))
    let messages = await transport.snapshot()
    #expect(messages.count == 2)
    guard case .request(.number(1), "initialize", let params) = messages[0] else {
      Issue.record("First message was not initialize request 1")
      return
    }
    #expect(params?.object?["processId"] == .integer(42))
    #expect(params?.object?["clientInfo"] != nil)
    #expect(params?.object?["rootUri"] == .null)
    #expect(params?.object?["workspaceFolders"] == .null)
    #expect(params?.object?["capabilities"]?.object?["notebookDocument"] != nil)
    #expect(messages[1] == .notification(method: "initialized", params: .object([:])))
    await connection.shutdown()
  }

  @Test("Application requests are rejected before initialization")
  func requestBeforeInitialize() async {
    let connection = JSONRPCConnection(transport: MockProcessTransport())
    await #expect(throws: JSONRPCConnectionError.notInitialized) {
      try await connection.request(method: "marimo/command")
    }
  }

  @Test("Requests are monotonic and responses release pending entries")
  func monotonicRequests() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    _ = try await connection.request(method: "first")
    _ = try await connection.request(method: "second")
    let ids = await transport.snapshot().compactMap { message -> UInt64? in
      guard case .request(.number(let id), _, _) = message else { return nil }
      return id
    }
    #expect(ids == [1, 2, 3])
    #expect(await connection.pendingRequestCount() == 0)
    await connection.shutdown()
  }

  @Test("Concurrent callers cannot reorder writes on the shared connection")
  func writesAreSerialized() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    await transport.delayWrite(for: "first-notification", by: .milliseconds(50))

    async let first: Void = connection.notify(method: "first-notification")
    try await Task.sleep(for: .milliseconds(5))
    async let second: Void = connection.notify(method: "second-notification")
    _ = try await (first, second)

    let methods = await transport.snapshot().compactMap { message -> String? in
      guard case .notification(let method, _) = message else { return nil }
      return method
    }
    #expect(methods.suffix(2) == ["first-notification", "second-notification"])
    await connection.shutdown()
  }

  @Test("Adapter emits the pinned notebook synchronization wire shape")
  func notebookSyncWireShape() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let sidecar = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: ".build/Sidecar")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar, connection: connection)
    try await adapter.start()
    let cell = NotebookSyncCell(
      runtimeID: UUID(),
      uri: "marimo-native-notebook-cell://document/cell",
      version: 1,
      text: "a😀b",
      metadata: ["marimo": .object(["name": .string("_")])]
    )
    let snapshot = NotebookSyncSnapshot(
      uri: "untitled:MarimoNative-document",
      version: 1,
      metadata: ["marimo": .object(["header": .null])],
      cells: [cell]
    )
    try await adapter.didOpenNotebook(snapshot)
    try await adapter.didOpenNotebook(snapshot)
    try await adapter.didChangeNotebook(
      uri: snapshot.uri,
      version: 2,
      change: .text(
        NotebookTextChange(
          cellURI: cell.uri,
          version: 2,
          range: LSPRange(
            start: LSPPosition(line: 0, character: 3),
            end: LSPPosition(line: 0, character: 3)
          ),
          text: "X"
        )
      )
    )

    let notifications = await transport.snapshot().compactMap {
      message -> (String, JSONValue?)? in
      guard case .notification(let method, let params) = message else { return nil }
      return (method, params)
    }
    #expect(
      notifications.map(\.0).suffix(4)
        == [
          "notebookDocument/didOpen", "notebookDocument/didClose",
          "notebookDocument/didOpen", "notebookDocument/didChange",
        ]
    )
    let opened = notifications[1].1?.object
    let notebook = opened?["notebookDocument"]?.object
    #expect(notebook?["notebookType"] == .string("marimo-notebook"))
    #expect(notebook?["version"] == .integer(1))
    #expect(notebook?["cells"]?.array?.first?.object?["kind"] == .integer(2))
    let textDocument = opened?["cellTextDocuments"]?.array?.first?.object
    #expect(textDocument?["languageId"] == .string("python"))
    #expect(textDocument?["text"] == .string("a😀b"))

    let changed = notifications.last?.1?.object?["change"]?.object
    let content = changed?["cells"]?.object?["textContent"]?.array?.first?.object
    #expect(content?["document"]?.object?["version"] == .integer(2))
    let range = content?["changes"]?.array?.first?.object?["range"]?.object
    #expect(range?["start"]?.object?["character"] == .integer(3))
    await adapter.shutdown()
  }

  @Test("Adapter orders save-session commands before graceful LSP shutdown")
  func saveAndShutdownWireShape() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let sidecar = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: ".build/Sidecar")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar, connection: connection)
    try await adapter.start()
    let document = OwnedNotebookDocumentV1(
      cells: [OwnedNotebookCell(code: "value = 1", name: "_")],
      header: ""
    )

    #expect(try await adapter.printNotebook(document) == "# printed exactly\r\n")
    try await adapter.moveSession(notebookURI: "untitled:old", newNotebookURI: "file:///new.py")
    try await adapter.closeSession(notebookURI: "file:///new.py")
    await adapter.shutdown()

    let messages = await transport.snapshot()
    let commandKinds = messages.compactMap { message -> String? in
      guard case .request(_, "marimo/command", let params) = message else { return nil }
      guard case .string(let kind) = params?.object?["kind"] else { return nil }
      return kind
    }
    #expect(
      commandKinds == [
        "print-notebook", "move-session", "close-session", "shutdown-all-sessions",
      ]
    )
    let shutdownIndex = messages.firstIndex {
      if case .request(_, "shutdown", _) = $0 { true } else { false }
    }
    let shutdownAllIndex = messages.firstIndex {
      guard case .request(_, "marimo/command", let params) = $0 else { return false }
      return params?.object?["kind"] == .string("shutdown-all-sessions")
    }
    #expect(shutdownAllIndex != nil)
    #expect(shutdownIndex != nil)
    if let shutdownAllIndex, let shutdownIndex {
      #expect(shutdownAllIndex < shutdownIndex)
    }
    #expect(messages.last == JSONRPCMessage.notification(method: "exit", params: nil))
  }

  @Test("Session-bound and restart commands use their exact pinned wire shape")
  func recoveryCommandWireShape() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let adapter = try MarimoLSPAdapter(
      sidecarDirectory: sidecarDirectory(), connection: connection)
    try await adapter.start()

    try await adapter.interrupt(notebookURI: "file:///notebook.py", kernelSessionID: "current")
    try await adapter.sendStdin(
      notebookURI: "file:///notebook.py", kernelSessionID: "current", text: "secret")
    try await adapter.restartSession(
      notebookURI: "file:///notebook.py",
      executable: "/venv/bin/python",
      workingDirectory: "/workspace",
      createIfMissing: false
    )

    let commands = await transport.snapshot().compactMap { message -> [String: JSONValue]? in
      guard case .request(_, "marimo/command", let params) = message else { return nil }
      return params?.object
    }
    let tail = Array(commands.suffix(3))
    #expect(Set(tail[0].keys) == ["kind", "notebookUri", "kernelSessionId"])
    #expect(tail[0]["kernelSessionId"] == .string("current"))
    #expect(Set(tail[1].keys) == ["kind", "notebookUri", "kernelSessionId", "text"])
    #expect(tail[1]["text"] == .string("secret"))
    #expect(
      Set(tail[2].keys)
        == ["kind", "notebookUri", "executable", "workingDirectory", "createIfMissing"]
    )
    #expect(tail[2]["kernelSessionId"] == nil)
    await adapter.shutdown()
  }

  @Test("Adapter restarts three times in 60 seconds and stops on the fourth crash")
  func boundedAutomaticRecovery() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let adapter = try MarimoLSPAdapter(
      sidecarDirectory: sidecarDirectory(), connection: connection)
    let events = await adapter.backendEvents()
    let collector = Task { () -> [MarimoBackendEvent] in
      var collected: [MarimoBackendEvent] = []
      for await event in events {
        collected.append(event)
        if case .automaticRestartStopped = event { return collected }
      }
      return collected
    }
    try await adapter.start()

    for expectedStartCount in 2...4 {
      await transport.terminate()
      try await waitUntil { await transport.recordedStartCount() == expectedStartCount }
    }
    await transport.emitStderr("fatal sidecar error\n")
    await transport.terminate()
    let collected = await collector.value

    #expect(await transport.recordedStartCount() == 4)
    #expect(collected.filter { if case .disconnected = $0 { true } else { false } }.count == 4)
    #expect(collected.filter { if case .restarted = $0 { true } else { false } }.count == 3)
    let stoppedLogs = collected.compactMap { event -> [String]? in
      guard case .automaticRestartStopped(let stderr) = event else { return nil }
      return stderr
    }
    #expect(stoppedLogs == [["fatal sidecar error"]])
    await adapter.shutdown()
  }

  @Test("Adapter force-terminates when graceful shutdown reaches five seconds")
  func boundedAdapterShutdown() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    let sidecar = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: ".build/Sidecar")
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar, connection: connection)
    try await adapter.start()
    await transport.disableAutomaticResponse(for: "marimo/command")

    let clock = ContinuousClock()
    let start = clock.now
    await adapter.shutdown()
    let elapsed = start.duration(to: clock.now)

    #expect(elapsed >= .seconds(5))
    #expect(elapsed < .seconds(6))
    #expect(await transport.processIdentifier() == nil)
    #expect(await connection.currentState() == .closed)
  }

  @Test("Timeout releases a pending request")
  func timeoutReleasesPending() async throws {
    let transport = MockProcessTransport()
    await transport.disableAutomaticResponse(for: "never")
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    await #expect(throws: JSONRPCConnectionError.self) {
      try await connection.request(method: "never", timeout: .milliseconds(10))
    }
    #expect(await connection.pendingRequestCount() == 0)
    await connection.shutdown()
  }

  @Test("Request classes use their normative timeout")
  func normativeTimeouts() {
    #expect(JSONRPCTimeouts.duration(method: "initialize", params: nil) == .seconds(10))
    #expect(JSONRPCTimeouts.duration(method: "shutdown", params: nil) == .seconds(5))
    #expect(
      JSONRPCTimeouts.duration(
        method: "marimo/command",
        params: .object(["kind": .string("parse-notebook")])
      ) == .seconds(120)
    )
    #expect(
      JSONRPCTimeouts.duration(
        method: "marimo/command",
        params: .object(["kind": .string("print-notebook")])
      ) == .seconds(120)
    )
    #expect(
      JSONRPCTimeouts.duration(method: "marimo/command", params: .object([:])) == .seconds(10))
  }

  @Test("Cancellation resumes and removes a pending request")
  func cancellationReleasesPending() async throws {
    let transport = MockProcessTransport()
    await transport.disableAutomaticResponse(for: "cancel-me")
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    let task = Task { try await connection.request(method: "cancel-me", timeout: .seconds(30)) }
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    await #expect(throws: JSONRPCConnectionError.self) { try await task.value }
    #expect(await connection.pendingRequestCount() == 0)
    await connection.shutdown()
  }

  @Test("Connection close releases pending requests")
  func closeReleasesPending() async throws {
    let transport = MockProcessTransport()
    await transport.disableAutomaticResponse(for: "close-me")
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    let task = Task { try await connection.request(method: "close-me", timeout: .seconds(30)) }
    try await Task.sleep(for: .milliseconds(10))
    await transport.terminate()
    await #expect(throws: JSONRPCConnectionError.self) { try await task.value }
    #expect(await connection.pendingRequestCount() == 0)
  }

  @Test("Unknown response IDs are recorded and ignored")
  func unknownResponse() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    try await transport.emit(.response(id: .number(999), result: .null))
    try await waitUntil { await connection.recordedUnknownResponseIDs() == [.number(999)] }
    #expect(await connection.currentState() == .ready)
    await connection.shutdown()
  }

  @Test("Required server requests receive valid responses")
  func serverRequests() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    try await transport.emit(
      .request(
        id: .string("config"),
        method: "workspace/configuration",
        params: .object(["items": .array([.object([:]), .object([:])])])
      )
    )
    try await transport.emit(
      .request(id: .number(80), method: "client/registerCapability", params: .object([:]))
    )
    try await transport.emit(
      .request(id: .number(82), method: "client/unregisterCapability", params: .object([:]))
    )
    try await transport.emit(.request(id: .number(81), method: "unsupported", params: nil))
    try await waitUntil { await transport.snapshot().count >= 6 }
    let messages = await transport.snapshot()
    #expect(messages.contains(.response(id: .string("config"), result: .array([.null, .null]))))
    #expect(messages.contains(.response(id: .number(80), result: .null)))
    #expect(messages.contains(.response(id: .number(82), result: .null)))
    #expect(
      messages.contains(
        .error(
          id: .number(81),
          error: JSONRPCErrorObject(code: -32601, message: "Method not found: unsupported")
        )
      )
    )
    await connection.shutdown()
  }

  @Test("Protocol text closes the connection")
  func invalidStdoutClosesConnection() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    await transport.emitRaw(Data("debug text\n".utf8))
    try await waitUntil { await connection.currentState() == .closed }
    #expect(await transport.processIdentifier() == nil)
  }

  @Test("Stderr retains only its last 200 lines")
  func boundedStderr() async throws {
    let transport = MockProcessTransport()
    let connection = JSONRPCConnection(transport: transport)
    _ = try await connection.startAndInitialize(request: launchRequest())
    await transport.emitStderr((0..<250).map { "line-\($0)" }.joined(separator: "\n") + "\n")
    try await waitUntil { await connection.stderrLines().count == 200 }
    let lines = await connection.stderrLines()
    #expect(lines.first == "line-50")
    #expect(lines.last == "line-249")
    await connection.shutdown()
  }

  private func launchRequest() -> ProcessLaunchRequest {
    ProcessLaunchRequest(executableURL: URL(fileURLWithPath: "/mock/python"), arguments: [])
  }

  private func sidecarDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: ".build/Sidecar")
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () async -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
      if clock.now >= deadline { throw JSONRPCConnectionError.timedOut(0, "test condition") }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}

extension JSONValue {
  fileprivate var object: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  fileprivate var array: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }
}
