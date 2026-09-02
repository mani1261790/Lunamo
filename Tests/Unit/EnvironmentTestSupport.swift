import Foundation
import MarimoEnvironment
import MarimoProcess

actor PreflightMockTransport: ProcessTransport {
  private let events: [ProcessEvent]
  private let finishes: Bool
  private var requests: [ProcessLaunchRequest] = []
  private var terminated = false

  init(events: [ProcessEvent], finishes: Bool = true) {
    self.events = events
    self.finishes = finishes
  }

  func start(_ request: ProcessLaunchRequest) -> AsyncStream<ProcessEvent> {
    requests.append(request)
    let events = self.events
    return AsyncStream { continuation in
      for event in events { continuation.yield(event) }
      if finishes { continuation.finish() }
    }
  }

  func write(_: Data) {}
  func terminate() { terminated = true }
  func processIdentifier() -> Int32? { nil }
  func recordedRequests() -> [ProcessLaunchRequest] { requests }
  func wasTerminated() -> Bool { terminated }
}

func successfulPreflight(
  executableURL: URL,
  python: [Int] = [3, 13, 1],
  architecture: String = "arm64",
  marimoVersion: String = "0.24.0"
) -> (PythonPreflightService, PreflightMockTransport) {
  let canonical = canonicalURL(executableURL)
  let data = Data(
    """
    {"executable":"\(canonical.path)","python":[\(python.map(String.init).joined(separator: ","))],"architecture":"\(architecture)","marimo_version":"\(marimoVersion)","marimo_file":"/tmp/site-packages/marimo/__init__.py"}
    """.utf8
  )
  let transport = PreflightMockTransport(events: [.stdout(data), .terminated(0)])
  return (PythonPreflightService(makeTransport: { transport }), transport)
}
