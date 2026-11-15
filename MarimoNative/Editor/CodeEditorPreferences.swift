import AppKit

public enum CodeEditorPreferences {
  public static let fontSizeKey = "editor.fontSize"
  public static let defaultFontSize: Double = 14
  public static let fontSizeRange: ClosedRange<Double> = 10...28

  public static func resolvedFontSize(_ value: Double) -> Double {
    guard value.isFinite else { return defaultFontSize }
    return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
  }
}

@MainActor
@discardableResult
func applyEditorFontSize(_ size: Double, to textView: NSTextView) -> Bool {
  // Changing attributes during IME composition can cancel the marked text.
  guard !textView.hasMarkedText() else { return false }
  let size = CGFloat(CodeEditorPreferences.resolvedFontSize(size))
  guard textView.font?.pointSize != size else { return false }
  let selection = textView.selectedRanges
  let undoManager = textView.undoManager
  undoManager?.disableUndoRegistration()
  defer { undoManager?.enableUndoRegistration() }
  textView.font = .monospacedSystemFont(ofSize: size, weight: .regular)
  textView.selectedRanges = selection
  return true
}
