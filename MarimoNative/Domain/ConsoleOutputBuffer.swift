import Foundation

public struct ConsoleOutputBuffer: Sendable, Equatable {
  public static let byteLimit = 10 * 1_024 * 1_024
  public static let lineLimit = 100_000
  public static let truncationNotice = "[Earlier console output was truncated.]\n"

  public private(set) var outputs: [MarimoOutput]
  private let maximumBytes: Int
  private let maximumLines: Int

  public init(
    outputs: [MarimoOutput] = [],
    maximumBytes: Int = byteLimit,
    maximumLines: Int = lineLimit
  ) {
    self.outputs = outputs
    self.maximumBytes = maximumBytes
    self.maximumLines = maximumLines
    trimIfNeeded()
  }

  public mutating func append(contentsOf newOutputs: [MarimoOutput]) {
    outputs.append(contentsOf: newOutputs)
    trimIfNeeded()
  }

  private mutating func trimIfNeeded() {
    let hadNotice = outputs.contains { $0.mimeType == Self.noticeMIMEType }
    outputs.removeAll { $0.mimeType == Self.noticeMIMEType }
    var bytes = outputs.reduce(0) { $0 + $1.estimatedByteCount }
    var lines = outputs.reduce(0) { $0 + $1.estimatedLineCount }
    var removeCount = 0
    while removeCount < outputs.count, bytes > maximumBytes || lines > maximumLines {
      bytes -= outputs[removeCount].estimatedByteCount
      lines -= outputs[removeCount].estimatedLineCount
      removeCount += 1
    }
    if removeCount > 0 { outputs.removeFirst(removeCount) }
    guard removeCount > 0 || hadNotice else { return }
    outputs.insert(
      MarimoOutput(
        channel: .stderr,
        mimeType: Self.noticeMIMEType,
        data: .string(Self.truncationNotice)
      ),
      at: 0
    )
  }

  private static let noticeMIMEType = "text/x-marimonative-truncation-notice"
}
