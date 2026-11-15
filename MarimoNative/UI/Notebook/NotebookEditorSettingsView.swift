import KeyboardShortcuts
import MarimoEditor
import SwiftUI

struct NotebookEditorSettingsView: View {
  @ObservedObject private var shortcuts = NotebookShortcutSettings.shared

  @AppStorage(CodeEditorPreferences.fontSizeKey)
  private var fontSize = CodeEditorPreferences.defaultFontSize

  var body: some View {
    Form {
      Section("Keyboard Shortcuts") {
        ForEach(NotebookShortcutAction.allCases) { action in
          KeyboardShortcuts.Recorder(
            NSLocalizedString(action.title, comment: ""),
            shortcut: Binding(
              get: { shortcuts.shortcut(for: action) },
              set: { _ = shortcuts.set($0, for: action) }
            )
          )
          .shortcutValidation { candidate in
            if let error = shortcuts.validationError(for: candidate, action: action) {
              return .disallow(reason: error)
            }
            return .allow
          }
        }
        if let message = shortcuts.validationMessage {
          Text(message).foregroundStyle(.red)
        }
        Text("Shortcuts work only while Lunamo is active.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Reset Keyboard Shortcuts") { shortcuts.reset() }
      }
      Section("Text Size") {
        Slider(
          value: Binding(
            get: { CodeEditorPreferences.resolvedFontSize(fontSize) },
            set: { fontSize = $0 }
          ),
          in: CodeEditorPreferences.fontSizeRange,
          step: 1
        ) {
          Text("Code Font Size")
        }
        .accessibilityValue("\(Int(CodeEditorPreferences.resolvedFontSize(fontSize))) pt")
        Text("\(Int(CodeEditorPreferences.resolvedFontSize(fontSize))) pt")
          .monospacedDigit()
        Text("print(\"Hello, Lunamo!\")")
          .font(
            .system(
              size: CodeEditorPreferences.resolvedFontSize(fontSize),
              design: .monospaced
            )
          )
          .padding(.vertical, 12)
        Button("Reset Text Size") {
          fontSize = CodeEditorPreferences.defaultFontSize
        }
      }
    }
    .formStyle(.grouped)
  }
}
