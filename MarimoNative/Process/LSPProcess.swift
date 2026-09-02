import Foundation

public enum ProcessEvent: Sendable, Equatable {
  case stdout(Data)
  case stderr(Data)
  case terminated(Int32)
}

public enum LSPProcessError: Error, Sendable, Equatable {
  case alreadyRunning
  case notRunning
  case stdinClosed
}

public protocol ProcessTransport: Sendable {
  func start(_ request: ProcessLaunchRequest) async throws -> AsyncStream<ProcessEvent>
  func write(_ data: Data) async throws
  func terminate() async
  func processIdentifier() async -> Int32?
}

public actor LSPProcess: ProcessTransport {
  private var process: Process?
  private var standardInput: FileHandle?
  private var standardOutput: Pipe?
  private var standardError: Pipe?

  public init() {}

  public func start(_ request: ProcessLaunchRequest) throws -> AsyncStream<ProcessEvent> {
    guard process == nil else { throw LSPProcessError.alreadyRunning }

    let process = Process()
    let input = Pipe()
    let output = Pipe()
    let errorPipe = Pipe()
    let (stream, continuation) = AsyncStream<ProcessEvent>.makeStream()

    process.executableURL = request.executableURL
    process.arguments = request.arguments
    process.environment = request.environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errorPipe

    output.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        continuation.yield(.stdout(data))
      }
    }
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      } else {
        continuation.yield(.stderr(data))
      }
    }
    process.terminationHandler = { process in
      continuation.yield(.terminated(process.terminationStatus))
      continuation.finish()
    }

    do {
      try process.run()
    } catch {
      output.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
      continuation.finish()
      throw error
    }
    self.process = process
    standardInput = input.fileHandleForWriting
    standardOutput = output
    standardError = errorPipe
    return stream
  }

  public func write(_ data: Data) throws {
    guard process?.isRunning == true else { throw LSPProcessError.notRunning }
    guard let standardInput else { throw LSPProcessError.stdinClosed }
    try standardInput.write(contentsOf: data)
  }

  public func terminate() {
    guard let process else { return }
    standardOutput?.fileHandleForReading.readabilityHandler = nil
    standardError?.fileHandleForReading.readabilityHandler = nil
    if process.isRunning { process.terminate() }
  }

  public func processIdentifier() -> Int32? {
    process?.isRunning == true ? process?.processIdentifier : nil
  }
}
