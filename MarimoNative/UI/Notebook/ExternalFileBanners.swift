import MarimoApplication
import SwiftUI

struct ExternalFileBanner: View {
  @ObservedObject var store: NotebookStore

  @ViewBuilder
  var body: some View {
    if !store.conflictBannerDismissed {
      switch store.externalFileState {
      case .changed(let target, let localDirty):
        changed(target: target, localDirty: localDirty)
      case .recovery(let target, _, let code, let cause):
        recovery(target: target, code: code, cause: cause)
      case .deleted(let target):
        deleted(target: target)
      case .none:
        EmptyView()
      }
    }
  }

  private func changed(target: URL, localDirty: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("File changed on disk", systemImage: "exclamationmark.triangle").font(.headline)
      Text(NotebookUserFacingError.Code.documentConflict.rawValue).font(.caption.monospaced())
      Text(target.path).font(.caption.monospaced()).foregroundStyle(.secondary)
      HStack {
        Button("Reload from Disk") { Task { await store.reloadPresentedFile() } }
        if localDirty {
          Button("Save Local Copy") { NotebookSaveActions.saveAs(store) }
          Button("Cancel") { store.dismissConflictBanner() }
        } else {
          Button("Ignore Until Next Save") { Task { await store.ignoreExternalChanges() } }
        }
      }
    }
    .bannerStyle(color: .orange)
  }

  private func recovery(target: URL, code: String, cause: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Disk source needs recovery", systemImage: "doc.text.magnifyingglass").font(.headline)
      Text(code).font(.caption.monospaced())
      Text(cause)
      Text(target.path).font(.caption.monospaced()).foregroundStyle(.secondary)
      HStack {
        Button("View Disk Source") { store.recoverySourcePresented = true }
        Button("Save Local Copy") { NotebookSaveActions.saveAs(store) }
        Button("Cancel") { store.dismissConflictBanner() }
      }
    }
    .bannerStyle(color: .orange)
  }

  private func deleted(target: URL) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Notebook file was deleted", systemImage: "trash.slash").font(.headline)
      Text(NotebookUserFacingError.Code.documentConflict.rawValue).font(.caption.monospaced())
      Text(target.path).font(.caption.monospaced()).foregroundStyle(.secondary)
      HStack {
        Button("Save As…") { NotebookSaveActions.saveAs(store) }
        Button("Close") { Task { await store.closeDiscardingChanges() } }
        Button("Recreate at Original Location") { Task { await store.recreatePresentedFile() } }
      }
    }
    .bannerStyle(color: .red)
  }
}

struct NotebookErrorBanner: View {
  @ObservedObject var store: NotebookStore

  @ViewBuilder
  var body: some View {
    if case .none = store.externalFileState, let error = store.userFacingError {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(error.code.rawValue).font(.caption.monospaced()).fontWeight(.semibold)
          Spacer()
          Button("Dismiss", systemImage: "xmark") { store.dismissUserFacingError() }
            .labelStyle(.iconOnly)
        }
        Text(error.cause)
        Text(error.target).font(.caption.monospaced()).foregroundStyle(.secondary)
        Text(localizedUI("Recovery: %@", error.recoveryActions.joined(separator: ", ")))
          .font(.caption).foregroundStyle(.secondary)
      }
      .bannerStyle(color: .red)
    }
  }
}

struct RecoverySourceView: View {
  @ObservedObject var store: NotebookStore

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(store.recoverySource ?? "")
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding()
      }
      .accessibilityLabel("Disk source read-only buffer")
      .navigationTitle("Disk Source")
      .toolbar { Button("Done") { store.recoverySourcePresented = false } }
    }
    .frame(minWidth: 720, minHeight: 520)
  }
}

extension View {
  fileprivate func bannerStyle(color: Color) -> some View {
    padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      .accessibilityElement(children: .contain)
  }
}
