import AppIdentity
import Foundation

public struct UserDefaultsDomain: PreferencesDomain {
    public enum Failure: Error { case synchronizeFailed }
    private let defaults: UserDefaults
    private let name: String

    public init(name: String, defaults: UserDefaults = .standard) {
        self.name = name
        self.defaults = defaults
    }

    public func read() throws -> [String: Any] {
        defaults.persistentDomain(forName: name) ?? [:]
    }

    public func replace(with values: [String: Any]) throws {
        defaults.setPersistentDomain(values, forName: name)
        guard defaults.synchronize() else { throw Failure.synchronizeFailed }
    }
}
