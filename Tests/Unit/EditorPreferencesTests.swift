import AppKit
import Foundation
import KeyboardShortcuts
import Testing

@testable import MarimoEditor

@Suite("Editor preferences", .serialized)
@MainActor
struct EditorPreferencesTests {
  @Test("Font changes preserve content, selection and text undo; marked text is deferred")
  func fontChange() {
    let view = CodeEditorContainerView().textView
    view.string = "print(42)"
    view.setSelectedRange(NSRange(location: 6, length: 2))
    view.insertText("7", replacementRange: NSRange(location: 6, length: 2))
    let selection = view.selectedRanges
    #expect(applyEditorFontSize(24, to: view))
    #expect(view.font?.pointSize == 24)
    #expect(view.string == "print(7)")
    #expect(view.selectedRanges == selection)
    view.undoManager?.undo()
    #expect(view.string == "print(42)")
    view.undoManager?.redo()
    #expect(view.string == "print(7)")
    view.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(!applyEditorFontSize(18, to: view))
    #expect(view.hasMarkedText())
    #expect(view.font?.pointSize == 24)
    view.unmarkText()
    #expect(applyEditorFontSize(18, to: view))
    #expect(CodeEditorPreferences.resolvedFontSize(.nan) == 14)
    #expect(CodeEditorPreferences.resolvedFontSize(100) == 28)
    #expect(CodeEditorPreferences.resolvedFontSize(0) == 10)
  }

  @Test("Native Undo and Redo actions use the focused editor history")
  func undoCommands() throws {
    let view = CodeEditorContainerView().textView
    view.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
    view.breakUndoCoalescing()
    let undo = NSMenuItem(
      title: "Undo", action: #selector(CommandTextView.undo(_:)), keyEquivalent: "z")
    let redo = NSMenuItem(
      title: "Redo", action: #selector(CommandTextView.redo(_:)), keyEquivalent: "z")
    #expect(view.validateMenuItem(undo))
    #expect(!view.validateMenuItem(redo))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
        windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z",
        isARepeat: false, keyCode: 6))
    #expect(view.performKeyEquivalent(with: event))
    #expect(view.string == "")
    #expect(view.validateMenuItem(redo))
    view.redo(nil)
    #expect(view.string == "hello")
  }

  @Test("Larger fonts increase TextKit cell height without changing code")
  func fontHeight() {
    let container = CodeEditorContainerView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    let source = (0..<10).map { "print(\($0))" }.joined(separator: "\n")
    container.textView.string = source
    container.layoutSubtreeIfNeeded()
    applyEditorFontSize(12, to: container.textView)
    let small = container.measuredContentHeight
    applyEditorFontSize(26, to: container.textView)
    let large = container.measuredContentHeight
    #expect(large > small)
    #expect(container.textView.string == source)
  }

  @Test("Shortcuts survive reload, reject collisions, support clearing and reset")
  func persistence() throws {
    let name = "Lunamo-shortcuts-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = NotebookShortcutSettings(defaults: defaults)
    #expect(
      settings.shortcut(for: .toggleAssistant)
        == KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .option]))
    let custom = KeyboardShortcuts.Shortcut(.r, modifiers: [.command, .shift])
    #expect(settings.set(custom, for: .runAndStay))
    #expect(!settings.set(custom, for: .runAll))
    #expect(settings.shortcut(for: .runAll) == NotebookShortcutAction.runAll.defaultShortcut)
    #expect(
      settings.set(KeyboardShortcuts.Shortcut(.z, modifiers: [.command]), for: .runAll) == false)
    #expect(settings.set(KeyboardShortcuts.Shortcut(.r), for: .runAll) == false)
    #expect(settings.set(nil, for: .moveUp))
    let reloaded = NotebookShortcutSettings(defaults: defaults)
    #expect(reloaded.shortcut(for: .runAndStay) == custom)
    #expect(reloaded.shortcut(for: .moveUp) == nil)
    reloaded.reset()
    let reset = NotebookShortcutSettings(defaults: defaults)
    for action in NotebookShortcutAction.allCases {
      #expect(reset.shortcut(for: action) == action.defaultShortcut)
    }
  }

  @Test("Editor uses changed binding and stops intercepting the old binding")
  func dispatch() throws {
    let name = "Lunamo-shortcut-dispatch-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = NotebookShortcutSettings(defaults: defaults)
    let view = CodeEditorContainerView().textView
    view.shortcutSettings = settings
    var commands: [CodeEditorCommand] = []
    view.commandHandler = { commands.append($0) }
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
      try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
          isARepeat: false, keyCode: code))
    }
    view.keyDown(with: try event(36, [.command]))
    #expect(commands == [.runAndStay])
    #expect(settings.set(.init(.r, modifiers: [.command, .shift]), for: .runAndStay))
    #expect(settings.editorCommand(for: try event(36, [.command])) == nil)
    #expect(view.performKeyEquivalent(with: try event(15, [.command, .shift])))
    #expect(commands == [.runAndStay, .runAndStay])
    view.setMarkedText(
      "に", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    view.keyDown(with: try event(36, [.shift]))
    #expect(commands.count == 2)
  }
}
