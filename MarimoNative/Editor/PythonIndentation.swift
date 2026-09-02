import Foundation

public enum PythonIndentation {
  public static let width = 4

  public static func transform(
    _ source: String,
    selectedRange: NSRange,
    dedent: Bool
  ) -> (source: String, selectedRange: NSRange) {
    let text = UTF16Text(source)
    let safeLocation = min(max(selectedRange.location, 0), text.length)
    let safeLength = min(max(selectedRange.length, 0), text.length - safeLocation)
    let lineRange = text.lineRange(for: NSRange(location: safeLocation, length: safeLength))
    let block = UTF16Text(text.substring(with: lineRange))
    var output = ""
    var removedBeforeSelection = 0
    var delta = 0
    var cursor = 0

    while cursor < block.length {
      let range = block.lineRange(for: NSRange(location: cursor, length: 0))
      let line = block.substring(with: range)
      if dedent {
        let prefix = line.prefix(while: { $0 == " " }).count
        let removed = min(width, prefix)
        output += String(line.dropFirst(removed))
        delta -= removed
        if cursor < safeLocation - lineRange.location { removedBeforeSelection += removed }
      } else {
        output += String(repeating: " ", count: width) + line
        delta += width
      }
      cursor = NSMaxRange(range)
    }

    let updated = text.replacingCharacters(in: lineRange, with: output)
    let selectionLocation =
      dedent
      ? max(lineRange.location, safeLocation - removedBeforeSelection)
      : safeLocation + width
    return (
      updated,
      NSRange(location: selectionLocation, length: max(0, safeLength + delta))
    )
  }
}
