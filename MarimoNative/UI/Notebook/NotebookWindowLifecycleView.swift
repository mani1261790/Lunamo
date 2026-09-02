import AppKit
import MarimoApplication
import SwiftUI

struct NotebookWindowLifecycleView: NSViewRepresentable {
  let store: NotebookStore

  func makeCoordinator() -> Coordinator { Coordinator(store: store) }

  func makeNSView(context: Context) -> LifecycleView {
    let view = LifecycleView()
    view.coordinator = context.coordinator
    return view
  }

  func updateNSView(_: LifecycleView, context: Context) {
    context.coordinator.store = store
  }

  static func dismantleNSView(_ view: LifecycleView, coordinator: Coordinator) {
    if view.window?.delegate === coordinator {
      view.window?.delegate = coordinator.originalDelegate
    }
  }

  final class LifecycleView: NSView {
    weak var coordinator: Coordinator?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let window { coordinator?.install(on: window) }
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSWindowDelegate {
    var store: NotebookStore
    nonisolated(unsafe) weak var originalDelegate: (any NSWindowDelegate)?
    private weak var installedWindow: NSWindow?
    private var allowingClose = false
    private var handlingClose = false

    init(store: NotebookStore) {
      self.store = store
    }

    func install(on window: NSWindow) {
      guard installedWindow !== window else { return }
      installedWindow = window
      originalDelegate = window.delegate
      window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      if allowingClose {
        return originalDelegate?.windowShouldClose?(sender) ?? true
      }
      guard !handlingClose else { return false }
      handlingClose = true
      if store.document.dirty {
        presentCloseConfirmation(for: sender)
      } else {
        closeDocumentThenWindow(sender, discardChanges: false)
      }
      return false
    }

    override func responds(to selector: Selector!) -> Bool {
      super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
      if originalDelegate?.responds(to: selector) == true { return originalDelegate }
      return super.forwardingTarget(for: selector)
    }

    private func presentCloseConfirmation(for window: NSWindow) {
      let alert = NSAlert()
      alert.messageText = "Save changes before closing?"
      alert.informativeText = "Unsaved changes in this notebook will be lost."
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Don't Save")
      alert.beginSheetModal(for: window) { [weak self, weak window] response in
        guard let self, let window else { return }
        switch response {
        case .alertFirstButtonReturn:
          NotebookSaveActions.save(self.store) { [weak self, weak window] saved in
            guard let self, let window else { return }
            if saved {
              self.closeDocumentThenWindow(window, discardChanges: false)
            } else {
              self.handlingClose = false
            }
          }
        case .alertThirdButtonReturn:
          self.closeDocumentThenWindow(window, discardChanges: true)
        default:
          self.handlingClose = false
        }
      }
    }

    private func closeDocumentThenWindow(_ window: NSWindow, discardChanges: Bool) {
      Task { @MainActor [weak self, weak window] in
        guard let self, let window else { return }
        if discardChanges {
          await store.closeDiscardingChanges()
        } else {
          await store.close()
        }
        allowingClose = true
        handlingClose = false
        window.performClose(nil)
      }
    }
  }
}
