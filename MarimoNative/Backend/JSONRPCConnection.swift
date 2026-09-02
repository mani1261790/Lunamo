import Foundation
import MarimoDomain
import MarimoProcess
import MarimoProtocol
import OSLog

public enum JSONRPCConnectionError: Error, Sendable, Equatable {
  case alreadyStarted
  case notStarted
  case notInitialized
  case closed
  case cancelled(UInt64)
  case requestIDExhausted
  case timedOut(UInt64, String)
  case requestFailed(JSONRPCErrorObject)
  case protocolFailure
  case processExited(Int32)
}

public struct JSONRPCInitializeRecord: Sendable, Equatable {
  public let serverInfo: JSONValue
  public let capabilities: JSONValue
}

public enum JSONRPCConnectionState: Sendable, Equatable {
  case idle
  case initializing
  case ready
  case shuttingDown
  case closed
}

public enum JSONRPCTimeouts {
  public static func duration(method: String, params: JSONValue?) -> Duration {
    if method == "initialize" { return .seconds(10) }
    if method == "shutdown" { return .seconds(5) }
    if method == "marimo/command",
      let kind = params?.objectValue?["kind"],
      kind == .string("parse-notebook") || kind == .string("print-notebook")
    {
      return .seconds(120)
    }
    return .seconds(10)
  }
}

public actor JSONRPCConnection {
  private struct PendingRequest {
    let method: String
    let continuation: CheckedContinuation<JSONValue, Error>
    let timeoutTask: Task<Void, Never>
  }

  private let transport: any ProcessTransport
  private let stderrBuffer: BoundedStderrBuffer
  private let logger = Logger(subsystem: "MarimoNative", category: "JSONRPCConnection")
  private var framer = JSONRPCFramer()
  private var state: JSONRPCConnectionState = .idle
  private var nextRequestID: UInt64 = 1
  private var pending: [UInt64: PendingRequest] = [:]
  private var eventTask: Task<Void, Never>?
  private var writeTail: Task<Void, Error>?
  private var writeSequence: UInt64 = 0
  private var initializeRecord: JSONRPCInitializeRecord?
  private var unknownResponseIDs: [JSONRPCID] = []
  private let notificationStream: AsyncStream<JSONRPCMessage>
  private let notificationContinuation: AsyncStream<JSONRPCMessage>.Continuation

  public init(
    transport: any ProcessTransport = LSPProcess(),
    stderrBuffer: BoundedStderrBuffer = BoundedStderrBuffer()
  ) {
    self.transport = transport
    self.stderrBuffer = stderrBuffer
    (notificationStream, notificationContinuation) = AsyncStream.makeStream()
  }

  deinit {
    eventTask?.cancel()
  }

  public func startAndInitialize(
    request launchRequest: ProcessLaunchRequest,
    rootURI: String? = nil,
    workspaceFolders: JSONValue = .null
  ) async throws -> JSONRPCInitializeRecord {
    guard state == .idle else { throw JSONRPCConnectionError.alreadyStarted }
    state = .initializing
    do {
      let events = try await transport.start(launchRequest)
      eventTask = Task { [weak self] in
        for await event in events {
          await self?.receive(event)
        }
      }
      let pid = await transport.processIdentifier().map(Int64.init) ?? 0
      let params: JSONValue = .object([
        "processId": .integer(pid),
        "clientInfo": .object(["name": .string("MarimoNative"), "version": .string("1.0")]),
        "rootUri": rootURI.map(JSONValue.string) ?? .null,
        "workspaceFolders": workspaceFolders,
        "capabilities": .object([
          "notebookDocument": .object([
            "synchronization": .object([
              "dynamicRegistration": .bool(false),
              "executionSummarySupport": .bool(false),
            ])
          ])
        ]),
      ])
      let result = try await requestInternal(
        method: "initialize",
        params: params,
        timeout: .seconds(10)
      )
      let resultObject = result.objectValue ?? [:]
      let record = JSONRPCInitializeRecord(
        serverInfo: resultObject["serverInfo"] ?? .null,
        capabilities: resultObject["capabilities"] ?? .null
      )
      initializeRecord = record
      logger.info("Captured serverInfo and server capabilities")
      try await send(.notification(method: "initialized", params: .object([:])))
      state = .ready
      return record
    } catch {
      state = .closed
      await transport.terminate()
      releaseAll(with: error)
      throw error
    }
  }

  public func request(
    method: String,
    params: JSONValue? = nil,
    timeout: Duration? = nil
  ) async throws -> JSONValue {
    guard state == .ready else {
      if state == .closed { throw JSONRPCConnectionError.closed }
      throw JSONRPCConnectionError.notInitialized
    }
    return try await requestInternal(
      method: method,
      params: params,
      timeout: timeout ?? JSONRPCTimeouts.duration(method: method, params: params)
    )
  }

  public func notify(method: String, params: JSONValue? = nil) async throws {
    guard state == .ready else {
      if state == .closed { throw JSONRPCConnectionError.closed }
      throw JSONRPCConnectionError.notInitialized
    }
    try await send(.notification(method: method, params: params))
  }

  public func shutdown() async {
    if state == .ready {
      _ = try? await requestInternal(method: "shutdown", params: .null, timeout: .seconds(5))
      if state != .closed {
        state = .shuttingDown
        try? await send(.notification(method: "exit", params: .null))
      }
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while state != .closed, clock.now < deadline, !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if state != .closed {
      await transport.terminate()
      state = .closed
      releaseAll(with: JSONRPCConnectionError.closed)
    }
    eventTask?.cancel()
    eventTask = nil
  }

  public func forceTerminate() async {
    await transport.terminate()
    state = .closed
    releaseAll(with: JSONRPCConnectionError.closed)
    eventTask?.cancel()
    eventTask = nil
  }

  public func currentState() -> JSONRPCConnectionState { state }

  public func recordedInitialize() -> JSONRPCInitializeRecord? { initializeRecord }

  public func recordedUnknownResponseIDs() -> [JSONRPCID] { unknownResponseIDs }

  public func pendingRequestCount() -> Int { pending.count }

  public func stderrLines() async -> [String] { await stderrBuffer.snapshot() }

  public func notifications() -> AsyncStream<JSONRPCMessage> { notificationStream }

  private func requestInternal(
    method: String,
    params: JSONValue?,
    timeout: Duration
  ) async throws -> JSONValue {
    guard nextRequestID != UInt64.max else {
      throw JSONRPCConnectionError.requestIDExhausted
    }
    let id = nextRequestID
    nextRequestID += 1
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let timeoutTask = Task { [weak self] in
          try? await Task.sleep(for: timeout)
          guard !Task.isCancelled else { return }
          await self?.timeOut(id: id)
        }
        pending[id] = PendingRequest(
          method: method,
          continuation: continuation,
          timeoutTask: timeoutTask
        )
        Task { [weak self] in
          await self?.sendPending(id: id, method: method, params: params)
        }
      }
    } onCancel: {
      Task { await self.cancel(id: id) }
    }
  }

  private func send(_ message: JSONRPCMessage) async throws {
    let payload = try JSONEncoder().encode(message)
    let framed = try JSONRPCFramer.frame(payload)
    let previous = writeTail
    let transport = self.transport
    writeSequence += 1
    let sequence = writeSequence
    let write = Task {
      if let previous { try await previous.value }
      try await transport.write(framed)
    }
    writeTail = write
    do {
      try await write.value
      if writeSequence == sequence { writeTail = nil }
    } catch {
      if writeSequence == sequence { writeTail = nil }
      throw error
    }
  }

  private func sendPending(id: UInt64, method: String, params: JSONValue?) async {
    guard pending[id] != nil else { return }
    do {
      try await send(.request(id: .number(id), method: method, params: params))
    } catch {
      fail(id: id, error: error)
    }
  }

  private func receive(_ event: ProcessEvent) async {
    switch event {
    case .stdout(let data):
      do {
        for payload in try framer.append(data) {
          try await receive(payload: payload)
        }
      } catch {
        logger.error("Protocol framing or decoding failed")
        await transport.terminate()
        state = .closed
        releaseAll(with: JSONRPCConnectionError.protocolFailure)
      }
    case .stderr(let data):
      await stderrBuffer.append(String(decoding: data, as: UTF8.self))
    case .terminated(let status):
      let wasExpected = state == .shuttingDown || state == .closed
      state = .closed
      releaseAll(
        with: wasExpected ? JSONRPCConnectionError.closed : .processExited(status)
      )
    }
  }

  private func receive(payload: Data) async throws {
    let message = try JSONDecoder().decode(JSONRPCMessage.self, from: payload)
    switch message {
    case .response(let id, let result):
      resolve(id: id, result: .success(result))
    case .error(let id, let error):
      if let id { resolve(id: id, result: .failure(.requestFailed(error))) }
    case .request(let id, let method, let params):
      try await answerServerRequest(id: id, method: method, params: params)
    case .notification:
      notificationContinuation.yield(message)
    }
  }

  private func answerServerRequest(
    id: JSONRPCID,
    method: String,
    params: JSONValue?
  ) async throws {
    switch method {
    case "workspace/configuration":
      let count = params?.objectValue?["items"]?.arrayValue?.count ?? 0
      try await send(.response(id: id, result: .array(Array(repeating: .null, count: count))))
    case "client/registerCapability", "client/unregisterCapability":
      try await send(.response(id: id, result: .null))
    default:
      try await send(
        .error(
          id: id,
          error: JSONRPCErrorObject(code: -32601, message: "Method not found: \(method)")
        )
      )
    }
  }

  private func resolve(
    id: JSONRPCID,
    result: Result<JSONValue, JSONRPCConnectionError>
  ) {
    guard case .number(let number) = id, let request = pending.removeValue(forKey: number) else {
      unknownResponseIDs.append(id)
      logger.debug("Ignoring unknown response id")
      return
    }
    request.timeoutTask.cancel()
    request.continuation.resume(with: result)
  }

  private func timeOut(id: UInt64) {
    guard let request = pending.removeValue(forKey: id) else { return }
    request.continuation.resume(throwing: JSONRPCConnectionError.timedOut(id, request.method))
  }

  private func cancel(id: UInt64) {
    guard let request = pending.removeValue(forKey: id) else { return }
    request.timeoutTask.cancel()
    request.continuation.resume(throwing: JSONRPCConnectionError.cancelled(id))
  }

  private func fail(id: UInt64, error: Error) {
    guard let request = pending.removeValue(forKey: id) else { return }
    request.timeoutTask.cancel()
    request.continuation.resume(throwing: error)
  }

  private func releaseAll(with error: Error) {
    let requests = Array(pending.values)
    pending.removeAll()
    for request in requests {
      request.timeoutTask.cancel()
      request.continuation.resume(throwing: error)
    }
    if state == .closed { notificationContinuation.finish() }
  }
}

extension JSONValue {
  fileprivate var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  fileprivate var arrayValue: [JSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }
}
