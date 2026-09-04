import MarimoApplication
import MarimoEnvironment
import SwiftUI

public struct NotebookSettingsView: View {
  @ObservedObject private var store: NotebookStore

  public init(store: NotebookStore) {
    self.store = store
  }

  public var body: some View {
    Form {
      Section("Python Execution") {
        LabeledContent("Status") {
          Label(status.title, systemImage: status.systemImage)
            .foregroundStyle(status.tint)
        }

        if let executable = status.executableURL {
          pathRow("Python Executable", url: executable)
        }
        if let workingDirectory = status.workingDirectory {
          pathRow("Working Directory", url: workingDirectory)
        }
        if let details = status.details {
          LabeledContent("Python", value: details.pythonVersion.description)
          LabeledContent("marimo", value: details.marimoVersion)
          LabeledContent("Architecture", value: details.architecture)
        }
        if let failure = status.failure {
          Text(failure.userMessage)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }

        HStack {
          Button("Choose Python Executable…") {
            NotebookEnvironmentActions.chooseExecutable(for: store)
          }
          Button("Choose Working Directory…") {
            NotebookEnvironmentActions.chooseWorkingDirectory(for: store)
          }
          Spacer()
          if let candidate = status.candidate {
            Button("Check Again") {
              Task { await store.selectPythonEnvironment(candidate) }
            }
            .disabled(status.isChecking)
          }
        }
      }

      Section("Execution Safety") {
        LabeledContent("Folder Trust", value: store.executionAuthorizationLabel)
        Text(
          "Opening a notebook never runs Python. The first Run asks before code is executed in the selected folder."
        )
        .foregroundStyle(.secondary)
      }

      Section {
        Text("Requires Python 3.10–3.14, Apple silicon, and marimo 0.24.0.")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 620, height: 500)
    .navigationTitle("Settings")
  }

  private func pathRow(_ label: LocalizedStringKey, url: URL) -> some View {
    LabeledContent(label) {
      Text(url.path)
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
  }

  private var status: EnvironmentStatusPresentation {
    EnvironmentStatusPresentation(state: store.environmentState)
  }
}

private struct EnvironmentStatusPresentation {
  let title: LocalizedStringKey
  let systemImage: String
  let tint: Color
  let executableURL: URL?
  let workingDirectory: URL?
  let details: PythonEnvironmentDetails?
  let failure: PythonPreflightFailure?
  let candidate: PythonEnvironmentCandidate?
  let isChecking: Bool

  init(state: NotebookEnvironmentState) {
    switch state {
    case .notConfigured:
      title = "Not Configured"
      systemImage = "exclamationmark.circle"
      tint = .secondary
      executableURL = nil
      workingDirectory = nil
      details = nil
      failure = nil
      candidate = nil
      isChecking = false
    case .selected(let selected, let directory):
      title = "Not Inspected"
      systemImage = "questionmark.circle"
      tint = .orange
      executableURL = selected.executableURL
      workingDirectory = directory
      details = nil
      failure = nil
      candidate = selected
      isChecking = false
    case .checking(let selected):
      title = "Checking…"
      systemImage = "clock"
      tint = .secondary
      executableURL = selected.executableURL
      workingDirectory = nil
      details = nil
      failure = nil
      candidate = selected
      isChecking = true
    case .invalid(let selected, let problem):
      title = "Failed"
      systemImage = "xmark.octagon.fill"
      tint = .red
      executableURL = selected.executableURL
      workingDirectory = nil
      details = nil
      failure = problem
      candidate = selected
      isChecking = false
    case .needsWorkingDirectory(let inspected):
      title = "Choose Working Directory"
      systemImage = "folder.badge.questionmark"
      tint = .orange
      executableURL = inspected.executableURL
      workingDirectory = nil
      details = inspected
      failure = nil
      candidate = Self.candidate(inspected)
      isChecking = false
    case .ready(let inspected, let directory):
      title = "Ready"
      systemImage = "checkmark.circle.fill"
      tint = .green
      executableURL = inspected.executableURL
      workingDirectory = directory
      details = inspected
      failure = nil
      candidate = Self.candidate(inspected)
      isChecking = false
    }
  }

  private static func candidate(_ details: PythonEnvironmentDetails) -> PythonEnvironmentCandidate {
    PythonEnvironmentCandidate(
      executableURL: details.executableURL,
      kind: details.kind,
      expectedIdentity: details.identity
    )
  }
}
