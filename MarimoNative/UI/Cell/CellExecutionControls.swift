import MarimoDomain
import MarimoEditor
import SwiftUI

extension CellView {
  var executionRail: some View {
    VStack(spacing: 8) {
      Button {
        if cell.runtime.status == .running {
          command(.interrupt)
        } else {
          command(.runAndStay)
        }
      } label: {
        executionControlLabel
          .frame(width: 20, height: 20)
      }
      .labelStyle(.iconOnly)
      .modifier(CellExecutionButtonStyle(prominent: isUnexecutedCell))
      .buttonBorderShape(.circle)
      .controlSize(.large)
      .disabled(cell.runtime.status == .running ? !canInterrupt : !canRun)
      .onHover { executionControlHovered = $0 }
      .animation(.easeOut(duration: 0.12), value: executionControlSymbol)
      .help(executionControlHelp)
      .accessibilityLabel(executionControlAccessibilityLabel)

      Text("[\(index)]")
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)

    }
    .frame(width: 44)
  }

  private var isUnexecutedCell: Bool {
    cell.runtime.status == .idle && !failedOrBlocked && cell.runtime.lastExecutedCode == nil
  }

  private var executionControlSymbol: String {
    if cell.runtime.status == .running {
      return executionControlHovered ? "stop.fill" : "progress.indicator"
    }
    if cell.runtime.wasInterrupted { return "stop.circle" }
    if failedOrBlocked { return "exclamationmark.triangle.fill" }
    if executionControlHovered { return "play.fill" }
    let completedCurrentSource = cell.runtime.successfullyExecuted(cell.code)
    return completedCurrentSource ? "checkmark" : "play.fill"
  }

  private var executionControlTint: Color {
    if cell.runtime.status == .running, executionControlHovered { return .red }
    return failedOrBlocked ? .orange : .primary
  }

  private var executionControlAccessibilityLabel: String {
    if cell.runtime.status == .running { return localizedUI("Cell is running. Stop execution") }
    if cell.runtime.wasInterrupted { return localizedUI("Execution stopped. Run again") }
    return failedOrBlocked
      ? localizedUI("Cell execution failed or was stopped. Run again") : localizedUI("Run Cell")
  }

  private var executionControlHelp: String {
    if cell.runtime.status == .running {
      return canInterrupt ? shortcutSettings.label(for: .interrupt) : localizedUI("Stopping…")
    }
    return canRun ? shortcutSettings.label(for: .runAndStay) : runDisabledHelp
  }

  var failedOrBlocked: Bool {
    cell.runtime.hasExecutionError || cell.runtime.status == .disabledTransitively
  }

  @ViewBuilder
  private var executionControlLabel: some View {
    if cell.runtime.status == .running, !executionControlHovered {
      ProgressView()
        .controlSize(.small)
        .tint(.accentColor)
    } else {
      Group {
        if isUnexecutedCell {
          Image(systemName: executionControlSymbol)
        } else {
          Image(systemName: executionControlSymbol)
            .foregroundStyle(executionControlTint)
        }
      }
      .contentTransition(.symbolEffect(.replace))
    }
  }

  @ViewBuilder
  func stdinField(_ prompt: StdinPromptState) -> some View {
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
}
