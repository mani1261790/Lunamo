import AppKit
import SwiftUI

public enum CodeEditorCommand: Sendable, Equatable {
  case runAndAdvance
  case runAndStay
  case runAndInsert
  case runAll
  case interrupt
  case moveUp
  case moveDown
  case deleteCell
  case leaveEditor
}

public enum CodeEditorMetrics {
  public static let minimumHeight: CGFloat = 72
  public static let maximumHeight: CGFloat = 1_600
  public static let fontSize: CGFloat = 14

  public static func presentation(for contentHeight: CGFloat) -> (height: CGFloat, scrolls: Bool) {
    (
      min(max(contentHeight, minimumHeight), maximumHeight),
      contentHeight > maximumHeight
    )
  }
}

enum CodeEditorFocusPolicy {
  static func shouldResignFirstResponder(wasFocused: Bool, isFocused: Bool) -> Bool {
    wasFocused && !isFocused
  }

  static func shouldApplyExternalText(
    stringsDiffer: Bool,
    hasMarkedText: Bool,
    isFocused: Bool,
    isFirstResponder: Bool
  ) -> Bool {
    stringsDiffer && !hasMarkedText && !isFocused && !isFirstResponder
  }
}

public struct CodeEditorView: NSViewRepresentable {
  public let text: String
  public let isFocused: Bool
  public let onTextChange: @MainActor @Sendable (String, Bool) -> Void
  public let onFocus: @MainActor @Sendable () -> Void
  public let onCommand: @MainActor @Sendable (CodeEditorCommand) -> Void
  public let onHeightChange: @MainActor @Sendable (CGFloat, Bool) -> Void

  public init(
    text: String,
    isFocused: Bool,
    onTextChange: @escaping @MainActor @Sendable (String, Bool) -> Void,
    onFocus: @escaping @MainActor @Sendable () -> Void,
    onCommand: @escaping @MainActor @Sendable (CodeEditorCommand) -> Void,
    onHeightChange: @escaping @MainActor @Sendable (CGFloat, Bool) -> Void
  ) {
    self.text = text
    self.isFocused = isFocused
    self.onTextChange = onTextChange
    self.onFocus = onFocus
    self.onCommand = onCommand
    self.onHeightChange = onHeightChange
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  public func makeNSView(context: Context) -> CodeEditorContainerView {
    let container = CodeEditorContainerView()
    container.textView.delegate = context.coordinator
    container.textView.commandHandler = { [weak coordinator = context.coordinator] command in
      coordinator?.parent.onCommand(command)
    }
    container.textView.string = text
    context.coordinator.container = container
    context.coordinator.scheduleHighlight(for: text)
    context.coordinator.measureHeight()
    return container
  }

  public func updateNSView(_ container: CodeEditorContainerView, context: Context) {
    context.coordinator.parent = self
    let isFirstResponder = container.window?.firstResponder === container.textView
    if CodeEditorFocusPolicy.shouldApplyExternalText(
      stringsDiffer: container.textView.string != text,
      hasMarkedText: container.textView.hasMarkedText(),
      isFocused: isFocused,
      isFirstResponder: isFirstResponder
    ) {
      let selection = container.textView.selectedRange()
      context.coordinator.isApplyingExternalText = true
      container.textView.string = text
      context.coordinator.isApplyingExternalText = false
      container.textView.setSelectedRange(
        NSRange(location: min(selection.location, UTF16Text(text).length), length: 0)
      )
      context.coordinator.scheduleHighlight(for: text)
    }
    let wasFocused = context.coordinator.wasFocused
    if isFocused, !isFirstResponder {
      container.window?.makeFirstResponder(container.textView)
    } else if CodeEditorFocusPolicy.shouldResignFirstResponder(
      wasFocused: wasFocused,
      isFocused: isFocused
    ), container.window?.firstResponder === container.textView {
      container.window?.makeFirstResponder(nil)
    }
    context.coordinator.wasFocused = isFocused
    context.coordinator.measureHeight()
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    fileprivate var parent: CodeEditorView
    fileprivate weak var container: CodeEditorContainerView?
    private let highlighter = PythonIncrementalHighlighter()
    private var highlightTask: Task<Void, Never>?
    fileprivate var isApplyingExternalText = false
    fileprivate var wasFocused = false
    private var lastHeight: CGFloat?
    private var lastScrollable: Bool?

    fileprivate init(parent: CodeEditorView) {
      self.parent = parent
    }

    public func textDidBeginEditing(_: Notification) {
      guard !parent.isFocused else { return }
      Task { @MainActor [weak self] in
        await Task.yield()
        self?.parent.onFocus()
      }
    }

    public func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      guard !isApplyingExternalText else { return }
      parent.onTextChange(textView.string, textView.hasMarkedText())
      scheduleHighlight(for: textView.string)
      measureHeight()
    }

    fileprivate func scheduleHighlight(for source: String) {
      highlightTask?.cancel()
      highlightTask = Task { [weak self, highlighter] in
        let spans = await highlighter.update(source: source)
        guard !Task.isCancelled else { return }
        self?.apply(spans: spans, source: source)
      }
    }

    fileprivate func measureHeight() {
      guard let container else { return }
      container.layoutSubtreeIfNeeded()
      let measured = container.measuredContentHeight
      let presentation = CodeEditorMetrics.presentation(for: measured)
      container.scrollView.hasVerticalScroller = presentation.scrolls
      guard lastHeight != presentation.height || lastScrollable != presentation.scrolls else {
        return
      }
      lastHeight = presentation.height
      lastScrollable = presentation.scrolls
      Task { @MainActor [weak self] in
        await Task.yield()
        self?.parent.onHeightChange(presentation.height, presentation.scrolls)
      }
    }

    private func apply(spans: [PythonSyntaxSpan], source: String) {
      guard let textView = container?.textView else { return }
      applyPythonSyntaxHighlight(spans: spans, source: source, to: textView)
    }
  }
}

@MainActor
@discardableResult
func applyPythonSyntaxHighlight(
  spans: [PythonSyntaxSpan],
  source: String,
  to textView: NSTextView
) -> Bool {
  guard textView.string == source, !textView.hasMarkedText(), let storage = textView.textStorage
  else { return false }
  let selection = textView.selectedRange()
  let fullRange = NSRange(location: 0, length: storage.length)
  textView.undoManager?.disableUndoRegistration()
  storage.beginEditing()
  storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
  for span in spans
  where NSMaxRange(NSRange(location: span.location, length: span.length)) <= storage.length {
    storage.addAttribute(
      .foregroundColor,
      value: color(for: span.kind),
      range: NSRange(location: span.location, length: span.length)
    )
  }
  storage.endEditing()
  textView.undoManager?.enableUndoRegistration()
  textView.setSelectedRange(selection)
  return true
}

private func color(for kind: PythonSyntaxKind) -> NSColor {
  switch kind {
  case .keyword: .systemPurple
  case .string: .systemRed
  case .comment: .secondaryLabelColor
  case .number: .systemBlue
  }
}

@MainActor
public final class CodeEditorContainerView: NSView {
  let scrollView = NSScrollView()
  let textView: CommandTextView
  private let textContentStorage = NSTextContentStorage()
  private let textLayoutManager = NSTextLayoutManager()

  override public init(frame frameRect: NSRect) {
    let textContainer = NSTextContainer(
      size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    textContentStorage.addTextLayoutManager(textLayoutManager)
    textLayoutManager.textContainer = textContainer
    textView = CommandTextView(frame: .zero, textContainer: textContainer)
    super.init(frame: frameRect)

    textContainer.widthTracksTextView = true
    textContainer.heightTracksTextView = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.minSize = NSSize(width: 0, height: CodeEditorMetrics.minimumHeight)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainerInset = NSSize(width: 12, height: 10)
    textView.font = .monospacedSystemFont(ofSize: CodeEditorMetrics.fontSize, weight: .regular)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = 2
    textView.defaultParagraphStyle = paragraphStyle
    textView.backgroundColor = .clear
    textView.drawsBackground = false
    textView.setAccessibilityLabel("Python code editor")

    scrollView.documentView = textView
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { nil }

  var measuredContentHeight: CGFloat {
    textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
    return textLayoutManager.usageBoundsForTextContainer.height + textView.textContainerInset.height
      * 2
  }
}

@MainActor
final class CommandTextView: NSTextView {
  var commandHandler: ((CodeEditorCommand) -> Void)?
  private let editorUndoManager = UndoManager()

  override var undoManager: UndoManager? { editorUndoManager }

  override func keyDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    switch event.keyCode {
    case 3 where modifiers == [.command]:
      showFindBar()
    case 36 where modifiers.contains([.command, .shift]):
      commandHandler?(.runAll)
    case 36 where modifiers.contains(.command):
      commandHandler?(.runAndStay)
    case 36 where modifiers.contains(.option):
      commandHandler?(.runAndInsert)
    case 36 where modifiers.contains(.shift):
      commandHandler?(.runAndAdvance)
    case 47 where modifiers.contains(.command):
      commandHandler?(.interrupt)
    case 48:
      applyIndentation(dedent: modifiers.contains(.shift))
    case 53:
      commandHandler?(.leaveEditor)
    case 126 where modifiers.contains([.command, .option]):
      commandHandler?(.moveUp)
    case 125 where modifiers.contains([.command, .option]):
      commandHandler?(.moveDown)
    default:
      super.keyDown(with: event)
    }
  }

  func showFindBar() {
    let sender = NSMenuItem()
    sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
    performFindPanelAction(sender)
  }

  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    guard !hasMarkedText(), let value = insertString as? String,
      let closing = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'"][value]
    else {
      super.insertText(insertString, replacementRange: replacementRange)
      return
    }
    let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
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
