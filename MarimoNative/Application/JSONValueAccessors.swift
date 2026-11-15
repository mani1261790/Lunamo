import MarimoDomain

extension Dictionary where Key == String, Value == JSONValue {
  func string(for key: String) -> String? {
    guard case .string(let value)? = self[key] else { return nil }
    return value
  }

  func bool(for key: String) -> Bool? {
    guard case .bool(let value)? = self[key] else { return nil }
    return value
  }

  func number(for key: String) -> Double? {
    switch self[key] {
    case .integer(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }
}
