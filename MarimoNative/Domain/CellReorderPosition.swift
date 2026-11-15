/// Converts a visual gap (0...count) to an index after removing the dragged cell.
public enum CellReorderPosition {
  public static func destination(source: Int, insertionBoundary: Int, count: Int) -> Int? {
    guard (0..<count).contains(source), (0...count).contains(insertionBoundary) else { return nil }
    let target = insertionBoundary > source ? insertionBoundary - 1 : insertionBoundary
    return target == source ? nil : target
  }
}
