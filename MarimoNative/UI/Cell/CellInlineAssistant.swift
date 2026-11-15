import MarimoEditor
import SwiftUI

extension CellView {
  var inlineAssistantPrompt: some View {
    HStack(spacing: 8) {
      Image(systemName: "sparkles")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Ask Assistant to change this code…", text: $inlineAssistantDraft)
        .textFieldStyle(.plain)
        .focused($inlineAssistantFocused)
        .onSubmit(submitInlineAssistant)
      Button("Cancel", systemImage: "xmark") {
        inlineAssistantPresented = false
        inlineAssistantDraft = ""
        focusEditor()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      Button("Send", systemImage: "arrow.up") { submitInlineAssistant() }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .disabled(inlineAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 42)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
        .allowsHitTesting(false)
    }
    .onAppear {
      Task { @MainActor in
        await Task.yield()
        inlineAssistantFocused = true
      }
    }
    .accessibilityLabel(localizedUI("Inline Assistant"))
  }

  func handleCodeEditorCommand(_ editorCommand: CodeEditorCommand) {
    if case .openInlineAssistant(let selection) = editorCommand {
      selectedCodeText = selection
      inlineAssistantPresented = true
      inlineAssistantDraft = ""
      return
    }
    if case .askAssistant(let action, let selection) = editorCommand {
      let prompt =
        switch action {
        case .explain:
          localizedUI("Explain this code clearly.")
        case .fixOrImprove:
          localizedUI(
            "Fix or improve this code. Return the complete replacement in one Python code block.")
        case .generateTests:
          localizedUI(
            "Generate useful tests for this code and return them in one Python code block.")
        }
      askAssistant(prompt, selection)
      return
    }
    command(editorCommand)
  }

  private func submitInlineAssistant() {
    let prompt = inlineAssistantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else { return }
    inlineAssistantPresented = false
    inlineAssistantDraft = ""
    askAssistant(prompt, selectedCodeText)
  }
}
