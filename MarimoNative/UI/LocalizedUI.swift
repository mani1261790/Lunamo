import Foundation

func localizedUI(_ key: String) -> String {
  Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

func localizedUI(_ key: String, _ arguments: CVarArg...) -> String {
  String(format: localizedUI(key), locale: Locale.current, arguments: arguments)
}
