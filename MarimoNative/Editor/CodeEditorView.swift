import AppKit
import MarimoDomain
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
  case openInlineAssistant(selection: String?)
  case askAssistant(CodeAssistantAction, selection: String?)
}

public enum CodeAssistantAction: Sendable, Equatable {
  case explain
  case fixOrImprove
  case generateTests
}

public enum CodeEditorMetrics {
  public static let minimumHeight: CGFloat = 52
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
  static func shouldBecomeFirstResponder(
    wasFocused: Bool,
    isFocused: Bool,
    isFirstResponder: Bool
  ) -> Bool {
    isFocused && !wasFocused && !isFirstResponder
  }

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
  @AppStorage(CodeEditorPreferences.fontSizeKey)
  private var fontSize = CodeEditorPreferences.defaultFontSize
  public let text: String
  public let isFocused: Bool
  public let onTextChange: @MainActor @Sendable (String, Bool) -> Void
  public let onFocus: @MainActor @Sendable () -> Void
  public let onCommand: @MainActor @Sendable (CodeEditorCommand) -> Void
  public let onSelectionChange: @MainActor @Sendable (String?) -> Void
  public let completionProvider:
    @MainActor @Sendable (String, Int, Int) async -> [PythonCompletionItem]
  public let onHeightChange: @MainActor @Sendable (CGFloat, Bool) -> Void
  public let accessibilityLabel: String

  public init(
    text: String,
    isFocused: Bool,
    onTextChange: @escaping @MainActor @Sendable (String, Bool) -> Void,
    onFocus: @escaping @MainActor @Sendable () -> Void,
    onCommand: @escaping @MainActor @Sendable (CodeEditorCommand) -> Void,
    onSelectionChange: @escaping @MainActor @Sendable (String?) -> Void = { _ in },
    completionProvider:
      @escaping @MainActor @Sendable (String, Int, Int) async
      -> [PythonCompletionItem] = { _, _, _ in [] },
    onHeightChange: @escaping @MainActor @Sendable (CGFloat, Bool) -> Void,
    accessibilityLabel: String = "Python code editor"
  ) {
    self.text = text
    self.isFocused = isFocused
    self.onTextChange = onTextChange
    self.onFocus = onFocus
    self.onCommand = onCommand
    self.onSelectionChange = onSelectionChange
    self.completionProvider = completionProvider
    self.onHeightChange = onHeightChange
    self.accessibilityLabel = accessibilityLabel
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
    container.textView.completionTriggerHandler = { [weak coordinator = context.coordinator] in
      coordinator?.scheduleCompletions(force: true)
    }
    container.textView.installContextMenu()
    container.textView.string = text
    container.textView.setAccessibilityLabel(accessibilityLabel)
    context.coordinator.container = container
    context.coordinator.updateFontSize()
    context.coordinator.scheduleHighlight(for: text)
    context.coordinator.measureHeight()
    return container
  }

  public func updateNSView(_ container: CodeEditorContainerView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.updateFontSize()
    container.textView.setAccessibilityLabel(accessibilityLabel)
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
    if CodeEditorFocusPolicy.shouldBecomeFirstResponder(
      wasFocused: wasFocused,
      isFocused: isFocused,
      isFirstResponder: isFirstResponder
    ) {
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
    private var completionTask: Task<Void, Never>?
    private var completionWords: [String] = []
    fileprivate var isApplyingExternalText = false
    fileprivate var wasFocused = false
    private var lastHeight: CGFloat?
    private var lastScrollable: Bool?
    private var lastMeasuredSource: String?
    private var lastMeasuredWidth: CGFloat?

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
      guard let textView = notification.object as? CommandTextView else { return }
      guard !isApplyingExternalText else { return }
      updateFontSize()
      parent.onTextChange(textView.string, textView.hasMarkedText())
      scheduleHighlight(for: textView.string)
      if textView.suppressAutomaticCompletion {
        textView.suppressAutomaticCompletion = false
      } else {
        scheduleCompletions(force: false)
      }
      measureHeight()
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      let range = textView.selectedRange()
      guard range.location != NSNotFound, range.length > 0,
        NSMaxRange(range) <= UTF16Text(textView.string).length
      else {
        parent.onSelectionChange(nil)
        return
      }
      parent.onSelectionChange((textView.string as NSString).substring(with: range))
    }

    public func textView(
      _: NSTextView,
      completions _: [String],
      forPartialWordRange _: NSRange,
      indexOfSelectedItem index: UnsafeMutablePointer<Int>?
    ) -> [String] {
      index?.pointee = 0
      return completionWords
    }

    fileprivate func scheduleCompletions(force: Bool) {
      completionTask?.cancel()
      guard let textView = container?.textView, !textView.hasMarkedText() else { return }
      let source = textView.string
      let cursor = textView.selectedRange().location
      guard cursor != NSNotFound, let position = Self.completionPosition(source, cursor: cursor),
        force || Self.shouldAutomaticallyComplete(source, cursor: cursor)
      else {
        completionWords = []
        return
      }
      completionTask = Task { @MainActor [weak self] in
        if !force { try? await Task.sleep(for: .milliseconds(180)) }
        guard !Task.isCancelled, let self else { return }
        let items = await parent.completionProvider(source, position.line, position.column)
        guard !Task.isCancelled, let current = container?.textView,
          current.string == source, current.selectedRange().location == cursor
        else { return }
        completionWords = items.map(\.label)
        if !completionWords.isEmpty { current.complete(nil) }
      }
    }

    static func completionPosition(_ source: String, cursor: Int) -> (line: Int, column: Int)? {
      guard cursor >= 0, cursor <= UTF16Text(source).length else { return nil }
      let prefix = (source as NSString).substring(to: cursor)
      let lines = prefix.components(separatedBy: "\n")
      return (max(0, lines.count - 1), lines.last?.unicodeScalars.count ?? 0)
    }

    static func shouldAutomaticallyComplete(_ source: String, cursor: Int) -> Bool {
      guard cursor > 0, cursor <= UTF16Text(source).length else { return false }
      let prefix = (source as NSString).substring(to: cursor)
      return prefix.last == "."
    }

    fileprivate func scheduleHighlight(for source: String) {
      highlightTask?.cancel()
      highlightTask = Task { [weak self, highlighter] in
        let spans = await highlighter.update(source: source)
        guard !Task.isCancelled else { return }
        self?.apply(spans: spans, source: source)
      }
    }

    fileprivate func updateFontSize() {
      guard let textView = container?.textView else { return }
      if applyEditorFontSize(parent.fontSize, to: textView) {
        lastMeasuredSource = nil
        lastMeasuredWidth = nil
      }
    }

    fileprivate func measureHeight() {
      guard let container else { return }
      let source = container.textView.string
      let width = container.bounds.width
      if lastMeasuredSource == source, let lastMeasuredWidth,
        abs(lastMeasuredWidth - width) <= 0.5
      {
        return
      }
      lastMeasuredSource = source
      lastMeasuredWidth = width
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
    scrollView.frame = bounds
    scrollView.autoresizingMask = [.width, .height]
    addSubview(scrollView)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) { nil }

  var measuredContentHeight: CGFloat {
    textLayoutManager.ensureLayout(for: textContentStorage.documentRange)
    return textLayoutManager.usageBoundsForTextContainer.height + textView.textContainerInset.height
      * 2
  }
}
