import AppKit

extension CommandTextView {
  func installContextMenu() {
    let menu = NSMenu()
    menu.addItem(withTitle: String(localized: "Cut"), action: #selector(cut(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: String(localized: "Copy"), action: #selector(copy(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: String(localized: "Paste"), action: #selector(paste(_:)), keyEquivalent: "")
    menu.addItem(.separator())

    let assistant = NSMenu()
    assistant.addItem(assistantItem("Explain Code", action: #selector(explainCode)))
    assistant.addItem(assistantItem("Fix or Improve Code", action: #selector(fixOrImproveCode)))
    assistant.addItem(assistantItem("Generate Tests", action: #selector(generateTests)))
    let assistantMenuItem = NSMenuItem(
      title: String(localized: "Assistant"), action: nil, keyEquivalent: "")
    assistantMenuItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
    assistantMenuItem.submenu = assistant
    menu.addItem(assistantMenuItem)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: String(localized: "Select All"), action: #selector(selectAll(_:)),
      keyEquivalent: "")
    self.menu = menu
  }

  private func assistantItem(_ title: String.LocalizationValue, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func explainCode() {
    commandHandler?(.askAssistant(.explain, selection: selectedSource()))
  }

  @objc private func fixOrImproveCode() {
    commandHandler?(.askAssistant(.fixOrImprove, selection: selectedSource()))
  }

  @objc private func generateTests() {
    commandHandler?(.askAssistant(.generateTests, selection: selectedSource()))
  }
}
