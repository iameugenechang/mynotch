import Foundation

/// A persistent domain, not registered defaults or the merged search list.
public protocol PreferencesDomain {
    func read() throws -> [String: Any]
    func replace(with values: [String: Any]) throws
}

public enum PreferencesMigration {
    public static let marker = "anotchup.identityMigration.v1"
    public enum Failure: Error { case invalidMarker, invalidPropertyList, verificationFailed }

    /// Destination values win, including false/empty values. Source is never modified.
    /// A completed migration does not resurrect keys later removed by the user.
    @discardableResult
    public static func run(source: any PreferencesDomain, destination: any PreferencesDomain) throws -> Bool {
        let current = try destination.read()
        if let markerValue = current[marker] {
            guard let value = markerValue as? String, value == "complete" else { throw Failure.invalidMarker }
            return false
        }
        var merged = try source.read()
        merged.removeValue(forKey: marker)
        merged.merge(current) { _, destinationValue in destinationValue }
        merged[marker] = "complete"
        guard PropertyListSerialization.propertyList(merged, isValidFor: .binary) else {
            throw Failure.invalidPropertyList
        }
        try destination.replace(with: merged)
        guard NSDictionary(dictionary: try destination.read()).isEqual(to: merged) else {
            throw Failure.verificationFailed
        }
        return true
    }
}
