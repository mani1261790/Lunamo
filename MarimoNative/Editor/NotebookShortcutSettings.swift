import AppKit
import Combine
import KeyboardShortcuts

public enum NotebookShortcutAction: String, CaseIterable, Identifiable, Sendable {
  case runAndAdvance, runAndStay, runAndInsert, runAll, interrupt, moveUp, moveDown
  case toggleAssistant

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .runAndAdvance: "Run Cell and Advance"
    case .runAndStay: "Run Cell"
    case .runAndInsert: "Run Cell and Insert Below"
    case .runAll: "Run All"
    case .interrupt: "Interrupt"
    case .moveUp: "Move Cell Up"
    case .moveDown: "Move Cell Down"
    case .toggleAssistant: "Toggle Assistant"
    }
  }

  public var defaultShortcut: KeyboardShortcuts.Shortcut {
    switch self {
    case .runAndAdvance: .init(.return, modifiers: [.shift])
    case .runAndStay: .init(.return, modifiers: [.command])
    case .runAndInsert: .init(.return, modifiers: [.option])
    case .runAll: .init(.return, modifiers: [.command, .shift])
    case .interrupt: .init(.period, modifiers: [.command])
    case .moveUp: .init(.upArrow, modifiers: [.command, .option])
    case .moveDown: .init(.downArrow, modifiers: [.command, .option])
    case .toggleAssistant: .init(.a, modifiers: [.command, .option])
    }
  }

  var editorCommand: CodeEditorCommand? {
    switch self {
    case .runAndAdvance: .runAndAdvance
    case .runAndStay: .runAndStay
    case .runAndInsert: .runAndInsert
    case .runAll: .runAll
    case .interrupt: .interrupt
    case .moveUp: .moveUp
    case .moveDown: .moveDown
    case .toggleAssistant: nil
    }
  }
}

@MainActor
public final class NotebookShortcutSettings: ObservableObject {
  public static let shared = NotebookShortcutSettings()
  static let storageKey = "editor.shortcuts.v1"

  private struct Saved: Codable {
    var shortcuts: [String: KeyboardShortcuts.Shortcut] = [:]
    var disabled: Set<String> = []
  }

  @Published private var saved: Saved
  @Published public private(set) var validationMessage: String?
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    saved =
      defaults.data(forKey: Self.storageKey)
      .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
  }

  public func shortcut(for action: NotebookShortcutAction) -> KeyboardShortcuts.Shortcut? {
    if saved.disabled.contains(action.rawValue) { return nil }
    return saved.shortcuts[action.rawValue] ?? action.defaultShortcut
  }

  public func validationError(
    for shortcut: KeyboardShortcuts.Shortcut?, action: NotebookShortcutAction
  ) -> String? {
    if let shortcut {
      if let conflict = NotebookShortcutAction.allCases.first(where: {
        $0 != action && self.shortcut(for: $0) == shortcut
      }) {
        return String(
          format: NSLocalizedString("Already used by %@.", comment: ""),
          NSLocalizedString(conflict.title, comment: "")
        )
      }
      if Self.reserved.contains(shortcut) {
        return NSLocalizedString(
          "This shortcut is reserved for a standard action.", comment: "")
      }
      if shortcut.modifiers.intersection([.command, .control, .option]).isEmpty,
        shortcut != action.defaultShortcut
      {
        return NSLocalizedString("Include Command, Control, or Option.", comment: "")
      }
    }
    return nil
  }

  @discardableResult
  public func set(_ shortcut: KeyboardShortcuts.Shortcut?, for action: NotebookShortcutAction)
    -> Bool
  {
    if let error = validationError(for: shortcut, action: action) {
      validationMessage = error
      return false
    }
    validationMessage = nil
    var next = saved
    next.shortcuts[action.rawValue] = shortcut
    if shortcut == nil {
      next.disabled.insert(action.rawValue)
    } else {
      next.disabled.remove(action.rawValue)
    }
    saved = next
    persist()
    return true
  }

  public func label(for action: NotebookShortcutAction) -> String {
    let title = NSLocalizedString(action.title, comment: "")
    guard let shortcut = shortcut(for: action) else { return title }
    return "\(title) (\(shortcut))"
  }

  public func reset() {
    validationMessage = nil
    saved = Saved()
    defaults.removeObject(forKey: Self.storageKey)
  }

  func editorCommand(for event: NSEvent) -> CodeEditorCommand? {
    guard let candidate = KeyboardShortcuts.Shortcut(event: event) else { return nil }
    return NotebookShortcutAction.allCases.first {
      shortcut(for: $0) == candidate
    }?.editorCommand
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(saved) {
      defaults.set(data, forKey: Self.storageKey)
    }
  }

  private static var reserved: Set<KeyboardShortcuts.Shortcut> {
    var result: Set<KeyboardShortcuts.Shortcut> = [
      .init(.space, modifiers: [.control]),
      .init(.delete, modifiers: [.command, .shift]),
      .init(.comma, modifiers: [.command]),
      .init(.f, modifiers: [.command, .control]),
      .init(.h, modifiers: [.command, .option]),
      .init(.s, modifiers: [.command, .shift]),
      .init(.z, modifiers: [.command, .shift]),
      .init(.tab, modifiers: [.control]),
      .init(.tab, modifiers: [.control, .shift]),
    ]
    for key: KeyboardShortcuts.Key in [.a, .c, .v, .x, .z, .s, .o, .q, .w, .h, .m, .f, .i] {
      result.insert(.init(key, modifiers: [.command]))
    }
    return result
  }
}
