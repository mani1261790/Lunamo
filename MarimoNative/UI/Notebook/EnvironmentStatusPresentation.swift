import MarimoEnvironment
import SwiftUI

struct EnvironmentStatusPresentation {
  let title: String
  let summary: String
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
      title = localizedUI("Choose a Python Environment")
      summary = localizedUI("Select a detected environment to get started.")
      systemImage = "exclamationmark.circle"
      tint = .secondary
      executableURL = nil
      workingDirectory = nil
      details = nil
      failure = nil
      candidate = nil
      isChecking = false
    case .selected(let selected, let directory):
      title = localizedUI("Python Has Not Been Checked")
      summary = localizedUI("This environment has not been checked yet.")
      systemImage = "questionmark.circle"
      tint = .orange
      executableURL = selected.executableURL
      workingDirectory = directory
      details = nil
      failure = nil
      candidate = selected
      isChecking = false
    case .checking(let selected):
      title = localizedUI("Checking Python…")
      summary = localizedUI("Checking Python, architecture, and marimo…")
      systemImage = "clock"
      tint = .secondary
      executableURL = selected.executableURL
      workingDirectory = nil
      details = nil
      failure = nil
      candidate = selected
      isChecking = true
    case .invalid(let selected, let problem):
      title = localizedUI("Python Check Failed")
      summary = localizedUI("This environment cannot run the notebook.")
      systemImage = "xmark.octagon.fill"
      tint = .red
      executableURL = selected.executableURL
      workingDirectory = nil
      details = nil
      failure = problem
      candidate = selected
      isChecking = false
    case .needsWorkingDirectory(let inspected):
      title = localizedUI("Choose a Working Folder")
      summary = localizedUI("Python is ready. Choose the folder used when this notebook runs.")
      systemImage = "folder.badge.questionmark"
      tint = .orange
      executableURL = inspected.executableURL
      workingDirectory = nil
      details = inspected
      failure = nil
      candidate = Self.candidate(inspected)
      isChecking = false
    case .ready(let inspected, let directory):
      title = localizedUI("Ready to Run")
      summary = localizedUI("Python and marimo are ready for this notebook.")
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
