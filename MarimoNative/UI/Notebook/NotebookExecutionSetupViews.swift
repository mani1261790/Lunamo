import MarimoApplication
import SwiftUI

extension NotebookRootView {
  @ViewBuilder
  var backendRecoveryBanner: some View {
    if store.backendRecoveryStopped {
      VStack(alignment: .leading, spacing: 8) {
        Label("Backend restart limit reached", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
        Text("Automatic restart stopped after three attempts in 60 seconds.")
          .foregroundStyle(.secondary)
        HStack {
          Button("Open Logs") { store.backendLogsPresented = true }
          Button("Restart Backend") { Task { await store.startBackend() } }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  @ViewBuilder
  var executionSetupBanner: some View {
    switch store.environmentState {
    case .ready:
      EmptyView()
    case .checking:
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("Checking Python…")
        Spacer()
        Button("Settings…") { openSettings() }
      }
      .executionSetupBannerStyle()
    case .notConfigured:
      environmentGuidance(
        title: "Choose a Python environment",
        message: "Select the Python installation and folder that will run this notebook."
      )
    case .selected:
      environmentGuidance(
        title: "Python has not been checked",
        message: "The first Run checks Python and marimo, then asks before executing code."
      )
    case .needsWorkingDirectory:
      workingFolderGuidance
    case .invalid(_, let failure):
      environmentGuidance(
        title: "Python cannot run this notebook", message: localizedPythonFailure(failure))
    }
  }

  @ViewBuilder
  func packageSetupBanner(confirmInstall: @escaping () -> Void) -> some View {
    if !store.missingPackages.isEmpty || store.packageOperationState.isRunning {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "shippingbox")
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Packages are required").font(.headline)
          Text(
            localizedUI(
              "This notebook needs: %@", store.missingPackages.joined(separator: ", ")
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Text(
            "They will be installed into this notebook's private environment, not into macOS or the app."
          )
          .font(.caption)
          .foregroundStyle(.tertiary)
        }
        Spacer(minLength: 12)
        if store.packageOperationState.isRunning {
          ProgressView().controlSize(.small)
        } else {
          Button("Install Packages…", systemImage: "arrow.down.circle", action: confirmInstall)
            .buttonStyle(.borderedProminent)
        }
      }
      .executionSetupBannerStyle()
    }

    if case .failed(let message) = store.packageOperationState {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        VStack(alignment: .leading, spacing: 3) {
          Text("Package installation failed").font(.headline)
          Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        Spacer()
        Button("Settings…") { openSettings() }
      }
      .executionSetupBannerStyle()
    }
  }

  private var workingFolderGuidance: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "folder.badge.questionmark")
        .font(.title3)
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text("Choose a working folder").font(.headline)
        Text(
          "The app folder is unavailable. Choose where this notebook can read and write files."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Choose Folder…", systemImage: "folder.badge.plus") {
        NotebookEnvironmentActions.chooseWorkingDirectory(for: store)
      }
      .buttonStyle(.borderedProminent)
      Button("Settings…") { openSettings() }
    }
    .executionSetupBannerStyle()
  }

  private func environmentGuidance(title: String, message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "terminal")
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(localizedUI(title)).font(.headline)
        Text(localizedUI(message)).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Settings…") { openSettings() }
    }
    .executionSetupBannerStyle()
  }
}
