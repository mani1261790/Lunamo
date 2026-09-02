import AppKit
import MarimoApplication
import MarimoUI

@MainActor
final class MarimoAppDelegate: NSObject, NSApplicationDelegate {
  weak var store: NotebookStore?
  private var terminationPending = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let store else { return .terminateNow }
    guard !terminationPending else { return .terminateLater }

    if store.document.dirty {
      let alert = NSAlert()
      alert.messageText = "Save changes before quitting?"
      alert.informativeText = "Unsaved notebook changes will be lost."
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Don't Save")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        terminationPending = true
        NotebookSaveActions.save(store) { [weak self] saved in
          guard let self else { return }
          if saved {
            self.finishTermination(sender, store: store)
          } else {
            self.terminationPending = false
            sender.reply(toApplicationShouldTerminate: false)
          }
        }
        return .terminateLater
      case .alertThirdButtonReturn:
        terminationPending = true
        finishTermination(sender, store: store)
        return .terminateLater
      default:
        return .terminateCancel
      }
    }

    terminationPending = true
    finishTermination(sender, store: store)
    return .terminateLater
  }

  private func finishTermination(_ sender: NSApplication, store: NotebookStore) {
    Task { @MainActor in
      await store.shutdownBackend()
      sender.reply(toApplicationShouldTerminate: true)
    }
  }
}
