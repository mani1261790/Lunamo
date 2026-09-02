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

  func start(_: ProcessLaunchRequest) -> AsyncStream<ProcessEvent> {
    running = true
    let (stream, continuation) = AsyncStream<ProcessEvent>.makeStream()
    self.continuation = continuation
    return stream
  }

  func write(_ data: Data) throws {
    for payload in try framer.append(data) {
      let message = try JSONDecoder().decode(JSONRPCMessage.self, from: payload)
      messages.append(message)
      if case .notification("exit", _) = message {
        terminate()
        continue
      }
      if case .request(let id, let method, _) = message,
        !methodsWithoutAutomaticResponse.contains(method)
      {
        let result: JSONValue =
          method == "initialize"
          ? .object([
            "serverInfo": .object(["name": .string("mock")]),
            "capabilities": .object(["notebookDocumentSync": .bool(true)]),
          ])
          : .object(["method": .string(method)])
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

  func disableAutomaticResponse(for method: String) {
    methodsWithoutAutomaticResponse.insert(method)
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
}
