import MarimoApplication
import MarimoEnvironment
import SwiftUI

struct NotebookPackageSettingsView: View {
  @ObservedObject var store: NotebookStore
  let showEnvironments: () -> Void
  @State private var query = ""
  @State private var requirement = ""
  @State private var confirmationPresented = false
  @State private var removeEnvironmentConfirmationPresented = false
  @State private var rebuildEnvironmentConfirmationPresented = false
  @State private var cleanupConfirmationPresented = false
  @State private var clearCacheConfirmationPresented = false
  @State private var environmentActionScope: ManagedPythonEnvironmentScope = .shared
  @State private var inputError: String?
  @FocusState private var packageFilterFocused: Bool
  @FocusState private var packageRequirementFocused: Bool

  var body: some View {
    Form {
      environmentChoiceSection
      if let details = store.selectedPythonEnvironment {
        environmentSection(details)
        addPackageSection
        installedPackagesSection
        Text("Requires Python 3.10–3.14, Apple silicon, and marimo 0.24.0.")
          .foregroundStyle(.secondary)
      } else {
        Section {
          VStack(spacing: 18) {
            ContentUnavailableView(
              "No Ready Environment", systemImage: "exclamationmark.triangle",
              description: Text("Choose a ready Python environment before viewing packages."))
            Button("Show Environments", action: showEnvironments)
              .buttonStyle(.borderedProminent)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 36)
        }
      }
      storageSection
    }
    .formStyle(.grouped)
    .contentMargins(.horizontal, 28, for: .scrollContent)
    .task { await store.refreshManagedEnvironmentStorage() }
    .confirmationDialog(
      localizedUI("Install this package in the selected environment?"),
      isPresented: $confirmationPresented,
      titleVisibility: .visible
    ) {
      Button(localizedUI("Install %@", requirement)) {
        let requested = requirement
        requirement = ""
        Task { await store.installPackages([requested]) }
      }
      Button(localizedUI("Cancel"), role: .cancel) {}
    } message: {
      Text(
        localizedUI(
          "Lunamo installs only into the app-managed environment selected above."
        ))
    }
    .confirmationDialog(
      "Move this environment to Trash?",
      isPresented: $removeEnvironmentConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive) {
        Task { await store.removeManagedEnvironment(environmentActionScope) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Notebooks are kept. Installed packages in this environment will be removed.")
    }
    .confirmationDialog(
      "Rebuild this environment?",
      isPresented: $rebuildEnvironmentConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Rebuild", role: .destructive) {
        Task { await store.rebuildManagedEnvironment(environmentActionScope) }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The current environment moves to Trash and a clean environment replaces it.")
    }
    .confirmationDialog(
      "Clean up unused project environments?",
      isPresented: $cleanupConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Move Unused Environments to Trash", role: .destructive) {
        Task { await store.cleanUnusedManagedEnvironments() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Only app-created project environments unused for at least 30 days are affected.")
    }
    .confirmationDialog(
      "Clear the package cache?",
      isPresented: $clearCacheConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("Move Cache to Trash", role: .destructive) {
        Task { await store.clearManagedPackageCache() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Installed environments are kept. Future installs may download packages again.")
    }
  }

  private var environmentChoiceSection: some View {
    Section {
      Picker(
        "Packages for this notebook",
        selection: Binding(
          get: { store.packageEnvironmentScope },
          set: { scope in Task { await store.setPackageEnvironmentScope(scope) } }
        )
      ) {
        Text("Shared").tag(ManagedPythonEnvironmentScope.shared)
        Text("This Project").tag(ManagedPythonEnvironmentScope.project)
      }
      .pickerStyle(.segmented)

      HStack(alignment: .top, spacing: 14) {
        Image(
          systemName: store.packageEnvironmentScope == .shared
            ? "person.2.fill" : "folder.badge.gearshape"
        )
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 34, height: 34)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        VStack(alignment: .leading, spacing: 4) {
          Text(
            store.packageEnvironmentScope == .shared
              ? localizedUI("Shared Environment") : localizedUI("Project Environment")
          )
          .font(.headline)
          Text(
            store.packageEnvironmentScope == .shared
              ? localizedUI(
                "Recommended. All notebooks use one package set, avoiding duplicate environments."
              )
              : localizedUI(
                "Use a separate package set only when this project needs different versions.")
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.vertical, 6)
    } header: {
      Text("Environment Strategy")
    } footer: {
      Text("Changing this selection never installs or removes packages by itself.")
    }
  }

  private func environmentSection(_ details: PythonEnvironmentDetails) -> some View {
    Section("Environment in Use") {
      HStack(spacing: 14) {
        Image(systemName: details.kind == .bundled ? "shippingbox.fill" : "terminal.fill")
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 34)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            details.kind == .bundled
              ? localizedUI("Built-in Python") : localizedUI(details.kind.displayName)
          )
          .font(.headline)
          Text(
            localizedUI(
              "Python %@ · marimo %@ · %@", details.pythonVersion.description,
              details.marimoVersion, details.architecture)
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          Text(details.executableURL.path)
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Text(
        selectedEnvironmentIsManaged
          ? localizedUI(
            "Notebook execution, package installation, and Terminal all use the environment shown here."
          )
          : localizedUI(
            "Execution and Terminal currently use this Python. Installing a package prepares the selected app-managed environment and switches to it."
          )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }

  private var selectedEnvironmentIsManaged: Bool {
    guard let executable = store.selectedPythonEnvironment?.executableURL,
      let current = store.managedEnvironmentSummaries.first(where: { $0.isCurrent })
    else { return false }
    return executable.standardizedFileURL
      == current.environmentURL.appending(path: "bin/python").standardizedFileURL
  }

  private var storageSection: some View {
    Section("Managed Storage") {
      ForEach(store.managedEnvironmentSummaries) { summary in
        managedEnvironmentRow(summary)
      }

      LabeledContent("Package Download Cache") {
        Text(byteCount(store.managedPackageCacheSize)).foregroundStyle(.secondary)
      }
      HStack {
        Button("Clean Up Unused…", systemImage: "clock.badge.checkmark") {
          cleanupConfirmationPresented = true
        }
        Button("Clear Cache…", systemImage: "trash") {
          clearCacheConfirmationPresented = true
        }
        .disabled(store.managedPackageCacheSize == 0)
      }
      if let message = store.environmentStorageMessage {
        Text(localizedUI(message))
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
  }

  private func managedEnvironmentRow(_ summary: ManagedPythonEnvironmentSummary) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 8) {
        Text(
          summary.scope == .shared
            ? localizedUI("Shared Environment") : localizedUI("Project Environment")
        )
        .font(.headline)
        if summary.isCurrent {
          Text("Current")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        Spacer()
        Text(summary.exists ? byteCount(summary.sizeBytes) : localizedUI("Not Created"))
          .foregroundStyle(.secondary)
      }
      Text(
        summary.lastUsedAt.map {
          localizedUI("Last used %@", $0.formatted(date: .abbreviated, time: .shortened))
        } ?? localizedUI("Not used yet")
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      Text(summary.environmentURL.path)
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
      if summary.exists {
        HStack {
          Button("Rebuild…", systemImage: "arrow.trianglehead.2.clockwise") {
            environmentActionScope = summary.scope
            rebuildEnvironmentConfirmationPresented = true
          }
          Button("Move to Trash…", systemImage: "trash", role: .destructive) {
            environmentActionScope = summary.scope
            removeEnvironmentConfirmationPresented = true
          }
        }
      }
    }
    .padding(.vertical, 6)
  }

  private func byteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private var addPackageSection: some View {
    Section("Add Package") {
      HStack(spacing: 9) {
        Image(systemName: "shippingbox")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("Package name, for example keras", text: $requirement)
          .textFieldStyle(.plain)
          .focused($packageRequirementFocused)
          .onSubmit { requestInstallation() }
        Button("Install…", systemImage: "arrow.down.circle") { requestInstallation() }
          .buttonStyle(PackageSettingsButtonStyle(prominent: true))
          .disabled(
            requirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || store.packageOperationState.isRunning)
      }
      .padding(.leading, 13)
      .padding(.trailing, 5)
      .padding(.vertical, 5)
      .background(Color(nsColor: .controlBackgroundColor), in: Capsule(style: .continuous))
      .overlay {
        Capsule(style: .continuous)
          .stroke(
            packageRequirementFocused ? Color.accentColor : Color(nsColor: .separatorColor),
            lineWidth: packageRequirementFocused ? 1.5 : 1
          )
          .allowsHitTesting(false)
      }
      .contentShape(Capsule(style: .continuous))
      .onTapGesture { packageRequirementFocused = true }
      if let inputError {
        Label(inputError, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
      }
      operationStatus
    }
  }

  @ViewBuilder
  private var operationStatus: some View {
    switch store.packageOperationState {
    case .preparingEnvironment:
      Label("Preparing the selected environment…", systemImage: "gearshape.2")
        .foregroundStyle(.secondary)
    case .installing(let packages):
      Label(
        localizedUI("Installing %@…", packages.joined(separator: ", ")),
        systemImage: "arrow.down.circle"
      )
      .foregroundStyle(.secondary)
    case .succeeded(let packages):
      Label(
        localizedUI("Installed %@", packages.joined(separator: ", ")),
        systemImage: "checkmark.circle.fill"
      )
      .foregroundStyle(.green)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .textSelection(.enabled)
    case .idle:
      Text(
        "Use package names such as keras or pandas==2.3. The app never installs into macOS or modifies its built-in Python."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }

  private var installedPackagesSection: some View {
    Section {
      HStack {
        Text(
          store.packagesLoaded
            ? localizedUI("%ld Installed Packages", store.installedPackages.count)
            : localizedUI("Installed Packages")
        )
        .foregroundStyle(.secondary)
        Spacer()
        if store.packagesLoading { ProgressView().controlSize(.small) }
        Button {
          Task { await store.refreshInstalledPackages() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(PackageSettingsButtonStyle(iconOnly: true))
        .disabled(store.packagesLoading)
        .help("Refresh")
        .accessibilityLabel("Refresh")
      }
      packageList
    }
  }

  @ViewBuilder
  private var packageList: some View {
    if let error = store.packagesError {
      Label(localizedPackageError(error), systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .textSelection(.enabled)
    } else if !store.packagesLoaded {
      ContentUnavailableView(
        "Package List Not Loaded", systemImage: "shippingbox",
        description: Text("Refresh to read packages from the environment shown above."))
    } else if store.installedPackages.isEmpty {
      ContentUnavailableView("No Installed Packages", systemImage: "shippingbox")
    } else {
      packageFilter
      ForEach(
        store.installedPackages.filter {
          let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
          return value.isEmpty || $0.name.localizedCaseInsensitiveContains(value)
            || $0.version.localizedCaseInsensitiveContains(value)
        }
      ) { package in
        LabeledContent(package.name, value: package.version)
      }
    }
  }

  private var packageFilter: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      TextField("Filter Packages", text: $query)
        .textFieldStyle(.plain)
        .focused($packageFilterFocused)
      if !query.isEmpty {
        Button {
          query = ""
          packageFilterFocused = true
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Package Filter")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    .overlay {
      Capsule()
        .stroke(
          packageFilterFocused ? Color.accentColor : Color(nsColor: .separatorColor),
          lineWidth: packageFilterFocused ? 1.5 : 1
        )
        .allowsHitTesting(false)
    }
    .contentShape(Capsule())
    .onTapGesture { packageFilterFocused = true }
  }

  private func requestInstallation() {
    let value = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    do {
      requirement = try UVNotebookPackageManager.validateRequirement(value)
      inputError = nil
      confirmationPresented = true
    } catch {
      inputError = error.localizedDescription
    }
  }

  private func localizedPackageError(_ error: String) -> String {
    if error == "Choose and validate a Python environment first." { return localizedUI(error) }
    let prefix = "Packages could not be read: "
    guard error.hasPrefix(prefix) else { return error }
    return localizedUI("Packages could not be read: %@", String(error.dropFirst(prefix.count)))
  }
}
