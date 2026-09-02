import Foundation
import MarimoDomain
import Testing

@Suite("JSONValue")
struct JSONValueTests {
  @Test("Round trips heterogeneous JSON without Any")
  func roundTrip() throws {
    let value: JSONValue = .object([
      "enabled": .bool(true),
      "count": .integer(3),
      "items": .array([.string("まりも"), .null]),
    ])

    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
  }
}
