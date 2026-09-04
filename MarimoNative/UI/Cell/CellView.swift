import MarimoApplication
import MarimoDomain
import MarimoEditor
import MarimoOutput
import MarimoWidgets
import SwiftUI

public struct CellView: View {
  private let cell: NotebookCellState
  private let index: Int
  private let selected: Bool
  private let focused: Bool
  private let canRun: Bool
  private let send: @MainActor @Sendable (NotebookIntent) -> Void
  private let focusEditor: @MainActor @Sendable () -> Void
  private let command: @MainActor @Sendable (CodeEditorCommand) -> Void
  private let submitStdin: @MainActor @Sendable (String) -> Void
  private let widgetStore: WidgetValueStore
  private let widgetsEnabled: Bool
  private let kernelSessionID: String?
  private let submitWidgetValue: @MainActor @Sendable (String, Double, String) -> Void

  @State private var editorHeight: CGFloat = 72
  @State private var internallyScrollable = false
  @State private var stdinText = ""

  public init(
    cell: NotebookCellState,
    index: Int = 1,
    selected: Bool,
    focused: Bool,
    canRun: Bool,
    send: @escaping @MainActor @Sendable (NotebookIntent) -> Void,
    focusEditor: @escaping @MainActor @Sendable () -> Void,
    command: @escaping @MainActor @Sendable (CodeEditorCommand) -> Void,
    submitStdin: @escaping @MainActor @Sendable (String) -> Void = { _ in },
    widgetStore: WidgetValueStore,
    widgetsEnabled: Bool,
    kernelSessionID: String?,
    submitWidgetValue: @escaping @MainActor @Sendable (String, Double, String) -> Void
  ) {
    self.cell = cell
    self.index = index
    self.selected = selected
    self.focused = focused
    self.canRun = canRun
    self.send = send
    self.focusEditor = focusEditor
    self.command = command
    self.submitStdin = submitStdin
    self.widgetStore = widgetStore
    self.widgetsEnabled = widgetsEnabled
    self.kernelSessionID = kernelSessionID
    self.submitWidgetValue = submitWidgetValue
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(spacing: 8) {
        Button {
          command(.runAndStay)
        } label: {
          Image(systemName: "play.fill")
            .frame(width: 20, height: 20)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(!canRun)
        .help(canRun ? "Run Cell (⌘↩)" : "Select a valid Python environment to run")
        .accessibilityLabel("Run Cell")

        Text("[\(index)]")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)

        cellStatus
      }
      .frame(width: 44)

      VStack(alignment: .leading, spacing: 10) {
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
        .background(
          Color(nsColor: .controlBackgroundColor),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              Color(nsColor: selected ? .controlAccentColor : .separatorColor),
              lineWidth: selected ? 1.5 : 1
            )
            .allowsHitTesting(false)
        }
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

        if let output = cell.runtime.output {
          OutputView(
            output: output,
            stale: cell.runtime.stale,
            running: cell.runtime.status == .running,
            widgetStore: widgetStore,
            widgetCellID: cell.runtimeID.uuidString,
            widgetsEnabled: widgetsEnabled,
            kernelSessionID: kernelSessionID,
            sendWidgetValue: submitWidgetValue
          )
        }

        ForEach(Array(cell.runtime.console.enumerated()), id: \.offset) { _, item in
          if item.channel != .stdin {
            OutputView(
              output: item,
              widgetStore: widgetStore,
              widgetCellID: cell.runtimeID.uuidString,
              widgetsEnabled: widgetsEnabled,
              kernelSessionID: kernelSessionID,
              sendWidgetValue: submitWidgetValue
            )
          }
        }
      }
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded {
        send(.selectCell(cell.runtimeID))
      }
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localizedUI("Cell %ld, %@", index, cell.name))
    .accessibilityValue(statusLabel(cell.runtime.status))
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

  @ViewBuilder
  private var cellStatus: some View {
    if cell.runtime.stale {
      Image(systemName: "clock.arrow.circlepath")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Stale")
        .accessibilityValue("Cell output is stale")
    } else {
      switch cell.runtime.status {
      case .idle:
        EmptyView()
      case .queued:
        Image(systemName: "clock")
          .font(.caption)
          .accessibilityLabel("Queued")
          .accessibilityValue("Waiting to run")
      case .running:
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Running")
          .accessibilityValue("Cell is running")
      case .error:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel("Error")
          .accessibilityValue("Cell execution failed")
      case .disabledTransitively:
        Image(systemName: "nosign")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Disabled")
          .accessibilityValue("Cell is disabled by a dependency")
      }
    }
  }
}

private func statusLabel(_ status: ExecutionStatus) -> String {
  switch status {
  case .idle: localizedUI("Idle")
  case .queued: localizedUI("Queued")
  case .running: localizedUI("Running")
  case .error: localizedUI("Error")
  case .disabledTransitively: localizedUI("Disabled")
  }
}
