import AppKit
import Foundation
import Testing

@testable import MarimoEditor

@Suite("TextKit code editor", .serialized)
struct CodeEditorTests {
  @Test("Indent and dedent use four spaces and never insert tabs")
  func indentation() {
    let source = "first\n  second\n"
    let selection = NSRange(location: 0, length: UTF16Text(source).length)
    let indented = PythonIndentation.transform(source, selectedRange: selection, dedent: false)
    #expect(indented.source == "    first\n      second\n")
    #expect(!indented.source.contains("\t"))

    let dedented = PythonIndentation.transform(
      indented.source,
      selectedRange: NSRange(location: 0, length: UTF16Text(indented.source).length),
      dedent: true
    )
    #expect(dedented.source == source)
  }

  @Test("Incremental highlighter reparses only the edited line within the input budget")
  func incrementalHighlighting() async {
    let highlighter = PythonIncrementalHighlighter()
    let original = (0..<500).map { "value_\($0) = \($0) # line" }.joined(separator: "\n")
    _ = await highlighter.update(source: original)
    let initialParsedLines = await highlighter.parsedLineCount()
    let edited = original.replacingOccurrences(of: "value_250", with: "return_value_250")
    let clock = ContinuousClock()
    let start = clock.now
    let spans = await highlighter.update(source: edited)
    let elapsed = start.duration(to: clock.now)

    #expect(initialParsedLines == 500)
    #expect(await highlighter.parsedLineCount() == 501)
    #expect(elapsed < .milliseconds(35))
    #expect(spans.contains { $0.kind == .comment })
    #expect(spans.contains { $0.kind == .number })
  }

  @Test("Editor height clamps to 72 through 1600 points")
  func sizing() {
    #expect(CodeEditorMetrics.presentation(for: 20).height == 72)
    #expect(!CodeEditorMetrics.presentation(for: 1_600).scrolls)
    #expect(CodeEditorMetrics.presentation(for: 2_400).height == 1_600)
    #expect(CodeEditorMetrics.presentation(for: 2_400).scrolls)
  }

  @Test("Editor is backed by TextKit 2 and keeps native editing services")
  @MainActor
  func textKitTwoServices() {
    let container = CodeEditorContainerView()
    #expect(container.textView.textLayoutManager != nil)
    #expect(container.textView.font?.pointSize == CodeEditorMetrics.fontSize)
    #expect(container.textView.textContainerInset == NSSize(width: 12, height: 10))
    #expect(container.textView.defaultParagraphStyle?.lineSpacing == 2)
    #expect(container.textView.allowsUndo)
    #expect(container.textView.usesFindBar)
    #expect(container.textView.isIncrementalSearchingEnabled)
    #expect(!container.textView.isRichText)
  }

  @Test("A click may establish focus before SwiftUI state catches up")
  func focusTransitionPolicy() {
    #expect(!CodeEditorFocusPolicy.shouldResignFirstResponder(wasFocused: false, isFocused: false))
    #expect(!CodeEditorFocusPolicy.shouldResignFirstResponder(wasFocused: false, isFocused: true))
    #expect(!CodeEditorFocusPolicy.shouldResignFirstResponder(wasFocused: true, isFocused: true))
    #expect(CodeEditorFocusPolicy.shouldResignFirstResponder(wasFocused: true, isFocused: false))
  }

  @Test("Focused local text is not replaced by a delayed SwiftUI value")
  func focusedTextReconciliationPolicy() {
    #expect(
      !CodeEditorFocusPolicy.shouldApplyExternalText(
        stringsDiffer: true,
        hasMarkedText: false,
        isFocused: true,
        isFirstResponder: true
      )
    )
    #expect(
      !CodeEditorFocusPolicy.shouldApplyExternalText(
        stringsDiffer: true,
        hasMarkedText: false,
        isFocused: false,
        isFirstResponder: true
      )
    )
    #expect(
      CodeEditorFocusPolicy.shouldApplyExternalText(
        stringsDiffer: true,
        hasMarkedText: false,
        isFocused: false,
        isFirstResponder: false
      )
    )
  }

  @Test("Native editor indents, pairs delimiters, and protects marked text")
  @MainActor
  func nativeEditingBehavior() throws {
    let container = CodeEditorContainerView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
    let textView = container.textView
    textView.frame = container.bounds

    textView.string = "line"
    textView.setSelectedRange(NSRange(location: 0, length: UTF16Text(textView.string).length))
    let tab = try #require(
      NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\t",
        charactersIgnoringModifiers: "\t",
        isARepeat: false,
        keyCode: 48
      )
    )
    textView.keyDown(with: tab)
    #expect(textView.string == "    line")
    #expect(!textView.string.contains("\t"))

    textView.string = ""
    textView.setSelectedRange(NSRange(location: 0, length: 0))
    textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string == "()")
    #expect(textView.selectedRange() == NSRange(location: 1, length: 0))

    textView.string = ""
    textView.setMarkedText(
      "に",
      selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    #expect(textView.hasMarkedText())
    textView.insertText("(", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.string != "()")
    textView.unmarkText()

    textView.string = "select me"
    textView.setSelectedRange(NSRange(location: 0, length: 6))
    #expect(textView.selectedRange() == NSRange(location: 0, length: 6))

    textView.string = ""
    textView.undoManager?.removeAllActions()
    textView.insertText("undoable", replacementRange: NSRange(location: NSNotFound, length: 0))
    textView.undoManager?.undo()
    #expect(textView.string == "")
    textView.undoManager?.redo()
    #expect(textView.string == "undoable")

    textView.string = "return 42"
    textView.setSelectedRange(NSRange(location: 7, length: 2))
    textView.undoManager?.removeAllActions()
    textView.insertText("7", replacementRange: NSRange(location: 7, length: 2))
    let selection = textView.selectedRange()
    let highlighted = applyPythonSyntaxHighlight(
      spans: [
        PythonSyntaxSpan(location: 0, length: 6, kind: .keyword),
        PythonSyntaxSpan(location: 7, length: 1, kind: .number),
      ],
      source: "return 7",
      to: textView
    )
    #expect(highlighted)
    #expect(textView.selectedRange() == selection)
    textView.undoManager?.undo()
    #expect(textView.string == "return 42")

    textView.setMarkedText(
      "に",
      selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    #expect(!applyPythonSyntaxHighlight(spans: [], source: textView.string, to: textView))
    textView.unmarkText()
  }

  @Test("Command-F is handled by the native find bar")
  func commandFBinding() throws {
    let source = try String(
      contentsOf: repositoryRoot().appending(path: "MarimoNative/Editor/CodeEditorView.swift"),
      encoding: .utf8
    )
    #expect(source.contains("case 3 where modifiers == [.command]"))
    #expect(source.contains("Int(NSFindPanelAction.showFindPanel.rawValue)"))
    #expect(source.contains("performFindPanelAction(sender)"))
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
