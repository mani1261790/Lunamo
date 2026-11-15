import MarimoApplication
import SwiftUI

extension NotebookRootView {
  private func toolbarIconButton(
    _ title: String, systemImage: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16))
        .frame(width: 16, height: 16)
    }
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.extraLarge)
    .accessibilityLabel(title)
  }

  var sidebarToggle: some View {
    toolbarIconButton(localizedUI("Toggle Sidebar"), systemImage: "sidebar.left") {
      sidebarPresented.toggle()
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .help(localizedUI("Toggle Sidebar"))
    .accessibilityLabel(localizedUI("Toggle Sidebar"))
  }

  var assistantToggle: some View {
    toolbarIconButton("Notebook Assistant", systemImage: "sparkles") {
      store.leaveEditor()
      store.assistantPresented.toggle()
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .help("On-device Notebook Assistant")
    .accessibilityLabel("Notebook Assistant")
  }

  var notebookToolbar: some View {
    HStack(spacing: 8) {
      if !sidebarPresented { sidebarToggle }
      Button {
        NotebookSaveActions.saveAs(store)
      } label: {
        Text(documentTitle)
          .fontWeight(.semibold)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .buttonStyle(.plain)
      .help(localizedUI("Name and Save…"))
      .accessibilityLabel(localizedUI("Name and Save Notebook"))
      .layoutPriority(-1)
      Spacer(minLength: 4)
      executionSummary
      toolbarIconButton("Toggle Terminal", systemImage: "terminal") {
        terminalPresented.toggle()
        if !terminalPresented {
          Task { await terminalSession.stop() }
        }
      }
      .help("Toggle Terminal")
      .accessibilityLabel("Toggle Terminal")
      Button {
        Task { await store.requestRunAll() }
      } label: {
        Label("Run All", systemImage: "play.fill")
          .labelStyle(.titleAndIcon)
          .font(.system(size: 13, weight: .semibold))
          .frame(height: 16)
      }
      .buttonStyle(.glassProminent)
      .buttonBorderShape(.capsule)
      .disabled(!canRun)
      .help(shortcutSettings.label(for: .runAll))
      .accessibilityLabel("Run All")
      if store.backendStatus == .ready {
        if store.forceRestartAvailable {
          toolbarIconButton(
            "Force Restart Kernel",
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
          ) {
            Task { await store.requestRestartKernel() }
          }
          .disabled(!store.sessionAllowsRestart)
        } else if store.sessionState == .running || store.sessionState == .interrupting {
          toolbarIconButton("Interrupt", systemImage: "stop.fill") {
            Task { await store.requestInterrupt() }
          }
          .disabled(!store.sessionAllowsInterrupt)
          .help(shortcutSettings.label(for: .interrupt))
          .accessibilityLabel("Interrupt")
        } else {
          toolbarIconButton("Restart Kernel", systemImage: "arrow.triangle.2.circlepath") {
            Task { await store.requestRestartKernel() }
          }
          .disabled(!store.sessionAllowsRestart)
          .help("Restart Kernel")
          .accessibilityLabel("Restart Kernel")
        }
      } else {
        toolbarIconButton("Restart Backend", systemImage: "arrow.clockwise") {
          Task { await store.startBackend() }
        }
      }

      if !store.assistantPresented { assistantToggle }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.glass)
    .buttonBorderShape(.circle)
    .controlSize(.extraLarge)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Notebook toolbar")
  }

}
