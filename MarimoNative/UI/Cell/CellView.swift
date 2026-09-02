import MarimoApplication
import MarimoDomain
import MarimoEditor
import SwiftUI

public struct CellView: View {
  private let cell: NotebookCellState
  private let selected: Bool
  private let focused: Bool
  private let canRun: Bool
  private let send: @MainActor @Sendable (NotebookIntent) -> Void
  private let focusEditor: @MainActor @Sendable () -> Void
  private let command: @MainActor @Sendable (CodeEditorCommand) -> Void
  private let submitStdin: @MainActor @Sendable (String) -> Void

  @State private var editorHeight: CGFloat = 72
  @State private var internallyScrollable = false
  @State private var hovering = false
  @State private var stdinText = ""

  public init(
    cell: NotebookCellState,
    selected: Bool,
    focused: Bool,
    canRun: Bool,
    send: @escaping @MainActor @Sendable (NotebookIntent) -> Void,
    focusEditor: @escaping @MainActor @Sendable () -> Void,
    command: @escaping @MainActor @Sendable (CodeEditorCommand) -> Void,
    submitStdin: @escaping @MainActor @Sendable (String) -> Void = { _ in }
  ) {
    self.cell = cell
    self.selected = selected
    self.focused = focused
    self.canRun = canRun
    self.send = send
    self.focusEditor = focusEditor
    self.command = command
    self.submitStdin = submitStdin
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(cell.name)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        cellStatus
        Spacer()
        if selected || hovering {
          Button("Run Cell", systemImage: "play.fill") {
            command(.runAndStay)
          }
          .buttonStyle(.borderless)
          .disabled(!canRun)
          .help(canRun ? "Run Cell (⌘↩)" : "Select a valid Python environment to run")
        }
      }

      CodeEditorView(
        text: cell.code,
        isFocused: focused,
        onTextChange: { text, hasMarkedText in
          send(
            .updateComposedCode(
              cellID: cell.runtimeID,
              code: text,
              hasMarkedText: hasMarkedText
            )
          )
        },
        onFocus: focusEditor,
        onCommand: command,
        onHeightChange: { height, scrollable in
          editorHeight = height
          internallyScrollable = scrollable
        }
      )
      .frame(height: editorHeight)
      .overlay(alignment: .topTrailing) {
        if internallyScrollable {
          Label("Scrollable editor", systemImage: "arrow.up.and.down")
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .padding(6)
            .accessibilityLabel("This cell has its own vertical scroll area")
        }
      }
      .overlay {
        if internallyScrollable {
          VStack(spacing: 0) {
            Divider()
            Spacer()
            Divider()
          }
          .allowsHitTesting(false)
        }
      }

      if let prompt = cell.runtime.stdinPrompt {
        stdinField(prompt)
      }

      if let output = plainText(from: cell.runtime.output), !output.isEmpty {
        Text(output)
          .font(.body.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityLabel("Cell text output")
      }

      ForEach(Array(cell.runtime.console.enumerated()), id: \.offset) { _, item in
        if !isStdin(item), let text = plainText(from: item), !text.isEmpty {
          Text(text)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .overlay(alignment: .leading) {
      if selected {
        Rectangle()
          .fill(Color.accentColor)
          .frame(width: 3)
          .accessibilityHidden(true)
      }
    }
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded {
        send(.selectCell(cell.runtimeID))
      }
    )
    .onHover { hovering = $0 }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Cell \(cell.name)")
  }

  @ViewBuilder
  private func stdinField(_ prompt: StdinPromptState) -> some View {
    HStack {
      if prompt.password {
        SecureField(prompt.prompt.isEmpty ? "Password" : prompt.prompt, text: $stdinText)
          .textFieldStyle(.roundedBorder)
          .onSubmit { submitCurrentStdin() }
      } else {
        TextField(prompt.prompt.isEmpty ? "Input" : prompt.prompt, text: $stdinText)
          .textFieldStyle(.roundedBorder)
          .onSubmit { submitCurrentStdin() }
      }
      if prompt.submitted {
        ProgressView().controlSize(.small)
      }
    }
    .disabled(prompt.submitted)
    .accessibilityLabel(prompt.password ? "Secure Python input" : "Python input")
  }

  private func submitCurrentStdin() {
    guard cell.runtime.stdinPrompt?.submitted == false else { return }
    let submitted = stdinText
    stdinText = ""
    submitStdin(submitted)
  }

  private func plainText(from value: JSONValue?) -> String? {
    guard let value else { return nil }
    switch value {
    case .string(let text):
      return text
    case .object(let object):
      guard object["mimetype"] == .string("text/plain") || object["mimetype"] == nil else {
        return nil
      }
      guard case .string(let text)? = object["data"] else { return nil }
      return text
    default:
      return nil
    }
  }

  private func isStdin(_ value: JSONValue) -> Bool {
    guard case .object(let object) = value else { return false }
    return object["channel"] == .string("stdin")
  }

  @ViewBuilder
  private var cellStatus: some View {
    if cell.runtime.stale {
      Label("Stale", systemImage: "clock.arrow.circlepath")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityValue("Cell output is stale")
    } else {
      switch cell.runtime.status {
      case .idle:
        EmptyView()
      case .queued:
        Label("Queued", systemImage: "clock")
          .font(.caption)
          .accessibilityValue("Waiting to run")
      case .running:
        HStack(spacing: 4) {
          ProgressView().controlSize(.small)
          Text("Running")
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityValue("Cell is running")
      case .error:
        Label("Error", systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityValue("Cell execution failed")
      case .disabledTransitively:
        Label("Disabled", systemImage: "nosign")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityValue("Cell is disabled by a dependency")
      }
    }
  }
}
