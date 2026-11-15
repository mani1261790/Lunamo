import AppKit
import MarimoApplication
import SwiftUI

struct TerminalConsoleView: NSViewRepresentable {
  @ObservedObject var session: NotebookTerminalSession

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder

    let textView = TerminalTextView()
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isEditable = true
    textView.isSelectable = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 14, height: 12)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
      width: 0,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.drawsBackground = false
    textView.insertionPointColor = .controlAccentColor
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.setAccessibilityLabel(localizedUI("Terminal"))
    context.coordinator.textView = textView
    context.coordinator.connectHandlers()
    context.coordinator.render(scrollToEnd: true)
    scrollView.documentView = textView

    DispatchQueue.main.async {
      textView.window?.makeFirstResponder(textView)
    }
    return scrollView
  }

  func updateNSView(_: NSScrollView, context: Context) {
    context.coordinator.parent = self
    context.coordinator.connectHandlers()
    context.coordinator.render(scrollToEnd: context.coordinator.renderedOutput != session.output)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: TerminalConsoleView
    fileprivate weak var textView: TerminalTextView?
    var renderedOutput = ""
    private var isRendering = false

    init(parent: TerminalConsoleView) {
      self.parent = parent
    }

    func connectHandlers() {
      textView?.terminalEnabled = parent.session.isRunning
      textView?.submitHandler = { [weak self] in
        guard let self else { return }
        Task { await self.parent.session.submit() }
      }
      textView?.previousHistoryHandler = { [weak self] in
        self?.parent.session.selectPreviousCommand()
      }
      textView?.nextHistoryHandler = { [weak self] in
        self?.parent.session.selectNextCommand()
      }
    }

    func render(scrollToEnd: Bool) {
      guard let textView else { return }
      let presentation = TerminalPresentation(
        output: parent.session.output,
        failureMessage: parent.session.failureMessage,
        command: parent.session.command
      )
      let display = presentation.prefix + parent.session.command
      let oldEditableStart = textView.editableStart
      let selection = textView.selectedRange()
      let commandOffset = max(0, selection.location - oldEditableStart)
      let commandSelectionLength = selection.location >= oldEditableStart ? selection.length : 0

      if textView.string != display {
        isRendering = true
        textView.textStorage?.setAttributedString(presentation.attributedString)
        textView.editableStart = (presentation.prefix as NSString).length
        let commandLength = (parent.session.command as NSString).length
        let location = textView.editableStart + min(commandOffset, commandLength)
        textView.setSelectedRange(
          NSRange(
            location: location,
            length: min(commandSelectionLength, commandLength - min(commandOffset, commandLength))
          )
        )
        isRendering = false
      }
      renderedOutput = parent.session.output
      if scrollToEnd {
        textView.scrollRangeToVisible(NSRange(location: (display as NSString).length, length: 0))
      }
    }

    func textDidChange(_ notification: Notification) {
      guard !isRendering, let textView = notification.object as? TerminalTextView else { return }
      let fullText = textView.string as NSString
      guard fullText.length >= textView.editableStart else { return }
      let command = fullText.substring(from: textView.editableStart)
      parent.session.updateCommand(command)
    }

    func textView(
      _ textView: NSTextView,
      shouldChangeTextIn affectedCharRange: NSRange,
      replacementString _: String?
    ) -> Bool {
      guard let textView = textView as? TerminalTextView else { return false }
      return affectedCharRange.location >= textView.editableStart
    }
  }
}

private struct TerminalPresentation {
  let prefix: String
  let attributedString: NSAttributedString

  init(output: String, failureMessage: String?, command: String) {
    var prefix = output
    if !prefix.isEmpty, !prefix.hasSuffix("\n") {
      prefix.append("\n")
    }
    var failureRange: NSRange?
    if let failureMessage, !failureMessage.isEmpty {
      let failure = "\(failureMessage)\n"
      failureRange = NSRange(
        location: (prefix as NSString).length, length: (failure as NSString).length)
      prefix.append(failure)
    }
    let promptRange = NSRange(location: (prefix as NSString).length, length: 2)
    prefix.append("❯ ")
    self.prefix = prefix

    let value = NSMutableAttributedString(
      string: prefix + command,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
        .foregroundColor: NSColor.textColor,
      ]
    )
    value.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: promptRange)
    if let failureRange {
      value.addAttribute(.foregroundColor, value: NSColor.systemRed, range: failureRange)
    }
    attributedString = value
  }
}

private final class TerminalTextView: NSTextView {
  var editableStart = 0
  var terminalEnabled = false
  var submitHandler: (() -> Void)?
  var previousHistoryHandler: (() -> Void)?
  var nextHistoryHandler: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    let commandAreaSelected = selectedRange().location >= editableStart
    switch event.keyCode {
    case 36,
      76 where terminalEnabled:
      submitHandler?()
    case 126 where commandAreaSelected:
      previousHistoryHandler?()
    case 125 where commandAreaSelected:
      nextHistoryHandler?()
    default:
      super.keyDown(with: event)
    }
  }
}
