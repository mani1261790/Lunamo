import Foundation
import MarimoDomain

extension MarimoLSPAdapter {
  public func textCell(source: String, markdown: String?) async throws -> TextCellProjection {
    let result = try await connection.request(
      method: "marimonative/textCell",
      params: .object([
        "source": .string(source), "markdown": markdown.map(JSONValue.string) ?? .null,
      ])
    )
    return try JSONDecoder().decode(TextCellProjection.self, from: JSONEncoder().encode(result))
  }
}
