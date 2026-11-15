import MarimoApplication
import MarimoEnvironment
import SwiftUI

public struct NotebookSettingsView: View {
  @ObservedObject private var store: NotebookStore
  @State private var tab = 0

  public init(store: NotebookStore) {
    self.store = store
  }

  public var body: some View {
    TabView(selection: $tab) {
      NotebookEditorSettingsView()
        .tabItem { Label("Editor", systemImage: "textformat") }
        .tag(2)
      executionSettings
        .tabItem { Label("Python Execution", systemImage: "terminal") }
        .tag(0)
      NotebookPackageSettingsView(store: store, showEnvironments: { tab = 0 })
        .tabItem { Label("Packages", systemImage: "shippingbox") }
        .tag(1)
    }
    .padding(.top, 12)
    .frame(minWidth: 740, idealWidth: 820, minHeight: 640, idealHeight: 740)
    .navigationTitle("Settings")
    .task { await store.refreshPythonEnvironments() }
    .onChange(of: tab) { _, selectedTab in
      guard selectedTab == 1, status.details != nil else { return }
      Task { await store.refreshInstalledPackages() }
    }
  }

  private var executionSettings: some View {
    Form {
      Section("Current Environment") {
        environmentOverview
          .padding(.vertical, 10)
        if let executable = status.executableURL {
          pathRow("Python Executable", url: executable)
        }
        if let workingDirectory = status.workingDirectory {
          pathRow(
            workingDirectory == store.applicationWorkspaceDirectory
              ? "App Folder" : "Working Directory",
            url: workingDirectory
          )
        }
      }

      if !readyCandidates.isEmpty {
        Section {
          ForEach(readyCandidates) { candidate in
            environmentRow(candidate)
          }
        } header: {
          Text("Ready to Use")
        } footer: {
          Text(
            "These Python environments meet all requirements. Untitled notebooks use the Lunamo app folder automatically."
          )
        }
      }

      if !otherCandidates.isEmpty {
        Section {
          ForEach(otherCandidates.prefix(5)) { candidate in
            environmentRow(candidate)
          }
          if otherCandidates.count > 5 {
            DisclosureGroup(
              localizedUI("%ld More Environments", otherCandidates.count - 5)
            ) {
              ForEach(otherCandidates.dropFirst(5)) { candidate in
                environmentRow(candidate)
              }
            }
          }
        } header: {
          Text("Needs Setup")
        } footer: {
          Text("Select an environment to see its exact requirement or repair it manually.")
        }
      }

      Section {
        HStack {
          Button("Scan Again", systemImage: "arrow.clockwise") {
            Task { await store.refreshPythonEnvironments() }
          }
          .buttonStyle(SettingsActionButtonStyle(prominent: true))
          .disabled(store.environmentsSearching)
          Spacer()
          Text("Selection is checked before any code runs.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text(
          "Lunamo searches common locations and nearby virtual environments automatically.")
      }

      Section("Advanced") {
        DisclosureGroup("Manual Setup") {
          ViewThatFits(in: .horizontal) {
            manualSetupActions(axis: .horizontal)
            manualSetupActions(axis: .vertical)
          }
          .padding(.top, 10)
        }
      }

      Section("Notebook Storage") {
        LabeledContent {
          Text(store.applicationWorkspaceDirectory.path)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.middle)
        } label: {
          Label("Default App Folder", systemImage: "folder.fill")
        }
        Text(
          "New notebooks start here. Choose another working directory only when a notebook needs files elsewhere."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      Section("Execution Safety") {
        LabeledContent(
          "Folder Trust", value: localizedUI(store.executionAuthorizationLabel))
        Label(
          "Opening a notebook never runs Python. The first Run asks before code is executed in the selected folder.",
          systemImage: "lock.shield"
        )
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .contentMargins(.horizontal, 28, for: .scrollContent)
  }

  private func manualSetupActions(axis: Axis) -> some View {
    Group {
      if axis == .horizontal {
        HStack(spacing: 10) {
          manualEnvironmentButtons
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          manualEnvironmentButtons
        }
      }
    }
    .buttonStyle(SettingsActionButtonStyle())
  }

  @ViewBuilder
  private var manualEnvironmentButtons: some View {
    Button {
      NotebookEnvironmentActions.chooseExecutable(for: store)
    } label: {
      Label("Choose Python Executable…", systemImage: "terminal")
    }
    Button {
      NotebookEnvironmentActions.chooseWorkingDirectory(for: store)
    } label: {
      Label("Choose Working Directory…", systemImage: "folder")
    }
    if let candidate = status.candidate {
      Button {
        Task { await store.selectPythonEnvironment(candidate) }
      } label: {
        Label("Check Again", systemImage: "checkmark.circle")
      }
      .disabled(status.isChecking)
    }
  }

  private var environmentOverview: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: status.systemImage)
        .font(.title2.weight(.semibold))
        .foregroundStyle(status.tint)
        .frame(width: 42, height: 42)
        .background(status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

      VStack(alignment: .leading, spacing: 5) {
        Text(status.title)
          .font(.title3.weight(.semibold))
        Text(status.summary)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let details = status.details {
          Text(
            localizedUI(
              "Python %@ · marimo %@ · %@", details.pythonVersion.description,
              details.marimoVersion, details.architecture)
          )
          .font(.callout.weight(.medium))
          .foregroundStyle(status.tint)
        }
      }

      Spacer(minLength: 20)
      if status.isChecking {
        ProgressView()
          .controlSize(.small)
          .padding(.top, 4)
      } else if needsWorkingDirectory {
        VStack(alignment: .trailing, spacing: 7) {
          Button("Choose Folder…", systemImage: "folder.badge.plus") {
            NotebookEnvironmentActions.chooseWorkingDirectory(for: store)
          }
          .buttonStyle(.borderedProminent)
          Text("Required before Run")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var needsWorkingDirectory: Bool {
    if case .needsWorkingDirectory = store.environmentState { return true }
    return false
  }

  private func environmentRow(_ candidate: PythonEnvironmentCandidate) -> some View {
    let selected = status.executableURL == candidate.executableURL
    let availability = store.environmentAvailability[candidate.id]
    return Button {
      Task { await store.selectPythonEnvironment(candidate) }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: candidate.kind == .bundled ? "shippingbox.fill" : "terminal.fill")
          .font(.title3)
          .foregroundStyle(selected ? Color.accentColor : .secondary)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(environmentName(candidate))
              .font(.headline)
            if candidate.kind == .bundled {
              Text("Recommended")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if selected {
              Text("Selected")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
          }
          Text(availabilitySummary(availability))
            .font(.callout)
            .foregroundStyle(availabilityTint(availability))
          Text(candidate.executableURL.path)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 16)
        availabilityBadge(availability)
      }
      .padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(status.isChecking)
    .accessibilityLabel(
      [
        environmentName(candidate),
        candidate.kind == .bundled ? localizedUI("Recommended") : nil,
        selected ? localizedUI("Selected") : nil,
        availabilitySummary(availability),
      ].compactMap { $0 }.joined(separator: ", ")
    )
  }

  private func environmentName(_ candidate: PythonEnvironmentCandidate) -> String {
    let launchPath = candidate.executableURL.path
    if launchPath.hasPrefix("/opt/homebrew/") || launchPath.hasPrefix("/usr/local/Homebrew/")
      || launchPath.hasPrefix("/usr/bin/") || launchPath.contains("/uv/python/")
    {
      return environmentName(candidate.kind, path: launchPath)
    }
    return environmentName(
      candidate.kind,
      path: candidate.expectedIdentity?.canonicalPath ?? launchPath
    )
  }

  private func environmentName(_ kind: PythonEnvironmentKind, path: String) -> String {
    if kind == .bundled {
      return localizedUI("Built-in Python")
    }
    if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/Homebrew/") {
      return localizedUI("Homebrew Python")
    }
    if path.hasPrefix("/usr/bin/") {
      return localizedUI("macOS System Python")
    }
    if let range = path.range(of: "/uv/python/") {
      let component = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
      let version =
        component.replacingOccurrences(of: "cpython-", with: "").split(separator: "-")
        .first.map(String.init) ?? component
      return localizedUI("uv Python %@", version)
    }
    return localizedUI(kind.displayName)
  }

  @ViewBuilder
  private func availabilityBadge(_ availability: PythonEnvironmentAvailability?) -> some View {
    switch availability {
    case .ready:
      Label("Ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .checking:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Checking")
    case .unavailable(let failure):
      Label(availabilityLabel(failure), systemImage: "exclamationmark.circle.fill")
        .foregroundStyle(availabilityTint(availability))
    case nil:
      Text("Not Checked")
        .foregroundStyle(.secondary)
    }
  }

  private func availabilitySummary(_ availability: PythonEnvironmentAvailability?) -> String {
    switch availability {
    case .ready(let details):
      localizedUI(
        "Python %@ · marimo %@ · %@", details.pythonVersion.description, details.marimoVersion,
        details.architecture)
    case .checking:
      localizedUI("Checking requirements…")
    case .unavailable(let failure):
      localizedPythonFailure(failure)
    case nil:
      localizedUI("Not checked yet")
    }
  }

  private func availabilityLabel(_ failure: PythonPreflightFailure) -> LocalizedStringKey {
    switch failure {
    case .marimoNotInstalled, .unsupportedMarimo:
      "Needs marimo"
    case .unsupportedPython, .unsupportedArchitecture:
      "Unsupported"
    default:
      "Unavailable"
    }
  }

  private func availabilityTint(_ availability: PythonEnvironmentAvailability?) -> Color {
    switch availability {
    case .ready:
      .green
    case .unavailable(let failure):
      switch failure {
      case .marimoNotInstalled, .unsupportedMarimo:
        .orange
      default:
        .red
      }
    case .checking, nil:
      .secondary
    }
  }

  private var readyCandidates: [PythonEnvironmentCandidate] {
    store.environmentCandidates.filter {
      if case .ready = store.environmentAvailability[$0.id] { return true }
      return false
    }
  }

  private var otherCandidates: [PythonEnvironmentCandidate] {
    store.environmentCandidates.filter {
      if case .ready = store.environmentAvailability[$0.id] { return false }
      return true
    }
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

private struct SettingsActionButtonStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    Control(configuration: configuration, prominent: prominent)
  }

  private struct Control: View {
    let configuration: ButtonStyle.Configuration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(.callout.weight(.medium))
        .labelStyle(.titleAndIcon)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .frame(minHeight: 30)
        .foregroundStyle(prominent ? Color.accentColor : Color.primary)
        .background {
          Capsule(style: .continuous)
            .fill(backgroundColor)
        }
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }

    private var backgroundColor: Color {
      if prominent {
        return Color.accentColor.opacity(configuration.isPressed ? 0.22 : hovering ? 0.16 : 0.1)
      }
      return Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.09 : 0.045)
    }

    private var borderColor: Color {
      if prominent {
        return Color.accentColor.opacity(hovering ? 0.48 : 0.28)
      }
      return Color.primary.opacity(hovering ? 0.22 : 0.1)
    }
  }
}
