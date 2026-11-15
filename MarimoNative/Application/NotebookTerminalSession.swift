import Combine
import Foundation
import MarimoProcess

@MainActor
public final class NotebookTerminalSession: ObservableObject {
  @Published public var command = ""
  @Published public private(set) var output = ""
  @Published public private(set) var isRunning = false
  @Published public private(set) var currentDirectoryURL: URL?
  @Published public private(set) var currentPythonEnvironmentURL: URL?
  @Published public private(set) var failureMessage: String?

  private let process: any ProcessTransport
  private var eventTask: Task<Void, Never>?
  private let maximumOutputCharacters = 262_144
  private var commandHistory: [String] = []
  private var historyIndex: Int?
  private var commandBeforeHistory = ""

  public init(process: any ProcessTransport = LSPProcess()) {
    self.process = process
  }

  public func start(in directoryURL: URL, pythonEnvironment: [String: String] = [:]) async {
    let environmentURL = pythonEnvironment["VIRTUAL_ENV"].map {
      URL(fileURLWithPath: $0, isDirectory: true)
    }
    if isRunning, currentDirectoryURL == directoryURL,
      currentPythonEnvironmentURL == environmentURL
    {
      return
    }
    await stop()

    var environment = ProcessInfo.processInfo.environment
    environment["TERM"] = "dumb"
    environment["PAGER"] = "cat"
    environment["GIT_PAGER"] = "cat"
    environment.merge(pythonEnvironment) { _, selected in selected }

    do {
      let events = try await process.start(
        ProcessLaunchRequest(
          executableURL: URL(fileURLWithPath: "/bin/zsh"),
          arguments: ["-l"],
          environment: environment,
          currentDirectoryURL: directoryURL
        )
      )
      currentDirectoryURL = directoryURL
      currentPythonEnvironmentURL = environmentURL
      failureMessage = nil
      isRunning = true
      append(localizedTerminalHeader(directoryURL))
      eventTask = Task { @MainActor [weak self] in
        for await event in events {
          guard !Task.isCancelled else { return }
          self?.receive(event)
        }
      }
    } catch {
      failureMessage = error.localizedDescription
      isRunning = false
    }
  }

  public func submit() async {
    guard isRunning else { return }
    let submittedCommand = command
    command = ""
    if !submittedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      commandHistory.removeAll { $0 == submittedCommand }
      commandHistory.append(submittedCommand)
      if commandHistory.count > 100 {
        commandHistory.removeFirst(commandHistory.count - 100)
      }
    }
    historyIndex = nil
    commandBeforeHistory = ""
    append("\(output.isEmpty || output.hasSuffix("\n") ? "" : "\n")❯ \(submittedCommand)\n")
    do {
      try await process.write(Data((submittedCommand + "\n").utf8))
    } catch {
      failureMessage = error.localizedDescription
      isRunning = false
    }
  }

  public func clear() {
    output = ""
  }

  public func updateCommand(_ value: String) {
    command = value
    historyIndex = nil
  }

  public func selectPreviousCommand() {
    guard !commandHistory.isEmpty else { return }
    if historyIndex == nil {
      commandBeforeHistory = command
      historyIndex = commandHistory.count - 1
    } else if let historyIndex, historyIndex > 0 {
      self.historyIndex = historyIndex - 1
    }
    if let historyIndex {
      command = commandHistory[historyIndex]
    }
  }

  public func selectNextCommand() {
    guard let historyIndex else { return }
    if historyIndex < commandHistory.count - 1 {
      self.historyIndex = historyIndex + 1
      command = commandHistory[historyIndex + 1]
    } else {
      self.historyIndex = nil
      command = commandBeforeHistory
      commandBeforeHistory = ""
    }
  }

  public func stop() async {
    eventTask?.cancel()
    eventTask = nil
    await process.terminate()
    isRunning = false
    currentDirectoryURL = nil
    currentPythonEnvironmentURL = nil
  }

  private func receive(_ event: ProcessEvent) {
    switch event {
    case .stdout(let data), .stderr(let data):
      append(String(decoding: data, as: UTF8.self))
    case .terminated(let status):
      isRunning = false
      if status != 0, failureMessage == nil {
        failureMessage = "Shell exited with status \(status)."
      }
    }
  }

  private func append(_ text: String) {
    output.append(text)
    if output.count > maximumOutputCharacters {
      output = String(output.suffix(maximumOutputCharacters))
    }
  }

  private func localizedTerminalHeader(_ directoryURL: URL) -> String {
    if let currentPythonEnvironmentURL {
      return
        "Terminal · \(directoryURL.path) · Python \(currentPythonEnvironmentURL.lastPathComponent)\n"
    }
    return "Terminal · \(directoryURL.path)\n"
  }
}
