import AppKit

@MainActor
final class CommandTextView: NSTextView {
  var shortcutSettings = NotebookShortcutSettings.shared
  var commandHandler: ((CodeEditorCommand) -> Void)?
  var completionTriggerHandler: (() -> Void)?
  var suppressAutomaticCompletion = false
  private let editorUndoManager = UndoManager()

  override var undoManager: UndoManager? { editorUndoManager }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard !hasMarkedText() else { return super.performKeyEquivalent(with: event) }
    if let command = shortcutSettings.editorCommand(for: event) {
      commandHandler?(command)
      return true
    }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if handleUndoKey(event) { return true }
    if event.keyCode == 34, modifiers == [.command] {
      openInlineAssistant(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    if hasMarkedText() {
      super.keyDown(with: event)
      return
    }
    if let command = shortcutSettings.editorCommand(for: event) {
      commandHandler?(command)
      return
    }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if handleUndoKey(event) { return }
    switch event.keyCode {
    case 3 where modifiers == [.command]:
      showFindBar()
    case 34 where modifiers == [.command]:
      commandHandler?(.openInlineAssistant(selection: selectedSource()))
    case 49 where modifiers == [.control]:
      completionTriggerHandler?()
    case 48:
      applyIndentation(dedent: modifiers.contains(.shift))
    case 53:
      commandHandler?(.leaveEditor)
    default:
      super.keyDown(with: event)
    }
  }

  @objc func undo(_ sender: Any?) {
    guard !hasMarkedText(), editorUndoManager.canUndo else { return }
    breakUndoCoalescing()
    editorUndoManager.undo()
  }

  @objc func redo(_ sender: Any?) {
    guard !hasMarkedText(), editorUndoManager.canRedo else { return }
    breakUndoCoalescing()
    editorUndoManager.redo()
  }

  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(undo(_:)): !hasMarkedText() && editorUndoManager.canUndo
    case #selector(redo(_:)): !hasMarkedText() && editorUndoManager.canRedo
    default: super.validateMenuItem(menuItem)
    }
  }

  private func handleUndoKey(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
    guard event.keyCode == 6 else { return false }
    if modifiers == [.command] {
      undo(nil)
      return true
    }
    if modifiers == [.command, .shift] {
      redo(nil)
      return true
    }
    return false
  }

  override func insertCompletion(
    _ word: String,
    forPartialWordRange charRange: NSRange,
    movement: Int,
    isFinal flag: Bool
  ) {
    // AppKit may call this repeatedly while previewing a completion. Never let a
    // completion edit immediately trigger another completion request.
    suppressAutomaticCompletion = true
    super.insertCompletion(
      word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
  }

  override func deleteBackward(_ sender: Any?) {
    suppressAutomaticCompletion = true
    let selection = selectedRange()
    if selection.length == 0, selection.location > 0,
      selection.location < UTF16Text(string).length
    {
      let source = string as NSString
      let opening = source.substring(
        with: NSRange(location: selection.location - 1, length: 1))
      let closing = source.substring(with: NSRange(location: selection.location, length: 1))
      if ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"][opening] == closing {
        insertText(
          "", replacementRange: NSRange(location: selection.location - 1, length: 2))
        return
      }
    }
    super.deleteBackward(sender)
  }

  override func deleteForward(_ sender: Any?) {
    suppressAutomaticCompletion = true
    super.deleteForward(sender)
  }

  func selectedSource() -> String? {
    let range = selectedRange()
    guard range.location != NSNotFound, range.length > 0,
      NSMaxRange(range) <= UTF16Text(string).length
    else { return nil }
    return (string as NSString).substring(with: range)
  }

  @objc func openInlineAssistant(_: Any?) {
    commandHandler?(.openInlineAssistant(selection: selectedSource()))
  }

  func showFindBar() {
    let sender = NSMenuItem()
    sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
    performFindPanelAction(sender)
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    guard !hasMarkedText(), let value = insertString as? String else {
      super.insertText(insertString, replacementRange: replacementRange)
      return
    }
    let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange

    if range.length == 0, range.location < UTF16Text(string).length,
      [")", "]", "}", "\"", "'"].contains(value),
      (string as NSString).substring(
        with: NSRange(location: range.location, length: UTF16Text(value).length)) == value
    {
      setSelectedRange(
        NSRange(location: range.location + UTF16Text(value).length, length: 0))
      return
    }

    guard let closing = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"][value]
    else {
      super.insertText(value, replacementRange: range)
      return
    }
    super.insertText(value + closing, replacementRange: range)
    setSelectedRange(NSRange(location: range.location + UTF16Text(value).length, length: 0))
  }

  private func applyIndentation(dedent: Bool) {
    let result = PythonIndentation.transform(
      string,
      selectedRange: selectedRange(),
      dedent: dedent
    )
    let fullRange = NSRange(location: 0, length: UTF16Text(string).length)
    insertText(result.source, replacementRange: fullRange)
    setSelectedRange(result.selectedRange)
  }
}
