public actor OutputAssetCache {
  public static let shared = OutputAssetCache(costLimit: 64 * 1_024 * 1_024)

  private struct Entry: Sendable {
    let value: PreparedOutput
    let cost: Int
    var access: UInt64
  }

  private let costLimit: Int
  private var entries: [String: Entry] = [:]
  private var totalCost = 0
  private var accessCounter: UInt64 = 0

  public init(costLimit: Int) {
    self.costLimit = max(0, costLimit)
  }

  public func value(for key: String) -> PreparedOutput? {
    guard var entry = entries[key] else { return nil }
    accessCounter &+= 1
    entry.access = accessCounter
    entries[key] = entry
    return entry.value
  }

  public func insert(_ value: PreparedOutput, for key: String, cost: Int) {
    if let previous = entries.removeValue(forKey: key) { totalCost -= previous.cost }
    guard cost <= costLimit else { return }
    accessCounter &+= 1
    entries[key] = Entry(value: value, cost: max(0, cost), access: accessCounter)
    totalCost += max(0, cost)
    while totalCost > costLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access })
    {
      totalCost -= oldest.value.cost
      entries.removeValue(forKey: oldest.key)
    }
  }

  public func entryCount() -> Int { entries.count }
}
