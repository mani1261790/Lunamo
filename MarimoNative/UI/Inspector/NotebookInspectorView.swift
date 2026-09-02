import MarimoApplication
import MarimoEnvironment
import SwiftUI

struct NotebookInspectorView: View {
  @ObservedObject var store: NotebookStore
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Form {
      Section("Session") {
        LabeledContent("Kernel", value: localizedSessionStatus)
        sessionEnvironment
        LabeledContent(
          "Session ID", value: store.document.kernelSessionID ?? localizedUI("Not Started"))
      }
      Section("Variables") {
        if store.variables.isEmpty {
          ContentUnavailableView(
            "No Variables",
            systemImage: "list.bullet.rectangle",
            description: Text("Run a cell to inspect variables.")
          )
        } else {
          ForEach(store.variables) { variable in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(variable.name).font(.body.monospaced()).textSelection(.enabled)
                Spacer()
                if let datatype = variable.datatype {
                  Text(datatype).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
              }
              if let preview = variable.preview {
                Text(preview).font(.caption.monospaced()).lineLimit(5).textSelection(.enabled)
              }
              if !variable.declaredBy.isEmpty {
                LabeledContent("Declared by", value: variable.declaredBy.joined(separator: ", "))
                  .font(.caption)
              }
              if !variable.usedBy.isEmpty {
                LabeledContent("Used by", value: variable.usedBy.joined(separator: ", "))
                  .font(.caption)
              }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(localizedUI("Variable %@", variable.name))
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(reduceTransparency || contrast == .increased ? .visible : .automatic)
    .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    .navigationTitle("Inspector")
  }

  @ViewBuilder
  private var sessionEnvironment: some View {
    switch store.environmentState {
    case .notConfigured:
      LabeledContent("Python Executable", value: localizedUI("Not Configured"))
      LabeledContent("Python", value: localizedUI("Unknown"))
      LabeledContent("marimo", value: localizedUI("Unknown"))
      LabeledContent(
        "Working Directory",
        value: store.notebookDirectoryURL?.path ?? localizedUI("Not Configured"))
    case .selected(let candidate, let workingDirectory):
      LabeledContent("Python Executable", value: candidate.executableURL.path)
      LabeledContent("Python", value: localizedUI("Not Inspected"))
      LabeledContent("marimo", value: localizedUI("Not Inspected"))
      LabeledContent(
        "Working Directory", value: workingDirectory?.path ?? localizedUI("Not Configured"))
    case .checking(let candidate):
      LabeledContent("Python Executable", value: candidate.executableURL.path)
      LabeledContent("Python", value: localizedUI("Checking…"))
    case .invalid(let candidate, let failure):
      LabeledContent("Python Executable", value: candidate.executableURL.path)
      Text(failure.userMessage).foregroundStyle(.red)
    case .needsWorkingDirectory(let details):
      inspectedEnvironment(details, workingDirectory: nil)
    case .ready(let details, let workingDirectory):
      inspectedEnvironment(details, workingDirectory: workingDirectory)
    }
  }

  @ViewBuilder
  private func inspectedEnvironment(_ details: PythonEnvironmentDetails, workingDirectory: URL?)
    -> some View
  {
    LabeledContent("Python Executable", value: details.executableURL.path)
    LabeledContent("Python", value: details.pythonVersion.description)
    LabeledContent("Architecture", value: details.architecture)
    LabeledContent("marimo", value: details.marimoVersion)
    LabeledContent(
      "Working Directory", value: workingDirectory?.path ?? localizedUI("Required"))
  }

  private var localizedSessionStatus: String {
    switch store.sessionState {
    case .notStarted: localizedUI("Not Started")
    case .starting: localizedUI("Starting")
    case .idle: localizedUI("Idle")
    case .running: localizedUI("Running")
    case .interrupting: localizedUI("Interrupting")
    case .restarting: localizedUI("Restarting")
    case .failed(let technicalDetail): "\(localizedUI("Failed")): \(technicalDetail)"
    case .closed: localizedUI("Closed")
    }
  }
}
