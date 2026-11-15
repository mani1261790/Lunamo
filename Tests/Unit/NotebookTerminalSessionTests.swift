import Foundation
import MarimoApplication
import MarimoProcess
import Testing

private actor TerminalMockTransport: ProcessTransport {
  private(set) var requests: [ProcessLaunchRequest] = []
  private(set) var writes: [Data] = []
  private(set) var terminated = false

  func start(_ request: ProcessLaunchRequest) -> AsyncStream<ProcessEvent> {
    requests.append(request)
    return AsyncStream { continuation in
      continuation.yield(.stdout(Data("ready\n".utf8)))
    }
  }

  func write(_ data: Data) {
    writes.append(data)
  }

  func terminate() {
    terminated = true
  }

  func processIdentifier() -> Int32? { 123 }
}

@Suite("Notebook Terminal")
struct NotebookTerminalSessionTests {
  @Test("Shell starts in the saved notebook directory and accepts explicit commands")
  @MainActor
  func startsInNotebookDirectory() async {
    let transport = TerminalMockTransport()
    let session = NotebookTerminalSession(process: transport)
    let directory = URL(fileURLWithPath: "/tmp/example-notebook", isDirectory: true)

    await session.start(
      in: directory,
      pythonEnvironment: [
        "PATH": "/tmp/example-notebook/.venv/bin:/usr/bin:/bin",
        "VIRTUAL_ENV": "/tmp/example-notebook/.venv",
      ]
    )
    session.command = "pwd"
    await session.submit()

    let requests = await transport.requests
    let writes = await transport.writes
    #expect(requests.count == 1)
    #expect(requests.first?.executableURL.path == "/bin/zsh")
    #expect(requests.first?.arguments == ["-l"])
    #expect(requests.first?.currentDirectoryURL == directory)
    #expect(requests.first?.environment["VIRTUAL_ENV"] == "/tmp/example-notebook/.venv")
    #expect(
      requests.first?.environment["PATH"]?.hasPrefix("/tmp/example-notebook/.venv/bin:") == true)
    #expect(writes == [Data("pwd\n".utf8)])
    #expect(session.output.contains("❯ pwd"))

    session.command = "echo one"
    await session.submit()
    session.command = "draft"
    session.selectPreviousCommand()
    #expect(session.command == "echo one")
    session.selectPreviousCommand()
    #expect(session.command == "pwd")
    session.selectNextCommand()
    #expect(session.command == "echo one")
    session.selectNextCommand()
    #expect(session.command == "draft")

    await session.stop()
    #expect(await transport.terminated)
  }
}
