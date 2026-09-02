public actor BoundedStderrBuffer {
  private let capacity: Int
  private var lines: [String] = []
  private var remainder = ""

  public init(capacity: Int = 200) {
    self.capacity = max(1, capacity)
  }

  public func append(_ text: String) {
    let combined = remainder + text
    var pieces = combined.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    remainder = pieces.popLast() ?? ""
    lines.append(contentsOf: pieces)
    if lines.count > capacity {
      lines.removeFirst(lines.count - capacity)
    }
  }

  public func snapshot() -> [String] {
    remainder.isEmpty ? lines : Array((lines + [remainder]).suffix(capacity))
  }
}
