import Foundation

public struct HUDMessage: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case brightness, volume, backlight, mic }
    public let show: Bool
    public let kind: Kind
    public let value: Double
    public let icon: String

    /// The legacy wire format encodes value as a string. Unknown kinds and
    /// non-finite or out-of-range values are invalid, not brightness or zero.
    public static func decode(_ data: Data) throws -> HUDMessage {
        struct Wire: Decodable { let show: Bool; let type: Kind; let value: String; let icon: String }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard let value = Double(wire.value), value.isFinite, (0...1).contains(value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid HUD value"))
        }
        return HUDMessage(show: wire.show, kind: wire.type, value: value, icon: wire.icon)
    }
}
