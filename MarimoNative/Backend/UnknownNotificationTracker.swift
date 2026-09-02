import MarimoProtocol

public actor UnknownNotificationTracker {
  private struct Key: Hashable {
    let sessionID: String
    let operation: String
  }

  private var counts: [Key: Int] = [:]

  public init() {}

  @discardableResult
  public func record(sessionID: String, notification: MarimoNotification) -> Bool {
    guard case .unknown(let operation, _) = notification else { return false }
    let key = Key(sessionID: sessionID, operation: operation)
    let count = counts[key, default: 0] + 1
    counts[key] = count
    return count <= 100
  }

  public func count(sessionID: String, operation: String) -> Int {
    counts[Key(sessionID: sessionID, operation: operation), default: 0]
  }
}
