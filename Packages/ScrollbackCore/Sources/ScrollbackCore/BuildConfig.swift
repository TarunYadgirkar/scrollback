import Foundation

/// Values that differ per developer (bundle ID prefix, iCloud container, App Group). project.yml copies
/// them from Config/Base.xcconfig into each target's Info.plist, so a fork changes them in one file.
enum BuildConfig {
    static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }
}
