import Foundation

extension AppDelegate {
    func appVersionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let displayVersion = version.flatMap { $0.isEmpty ? nil : $0 } ?? "1.0"
        return AppText.localized("版本 \(displayVersion)", "Version \(displayVersion)")
    }
}
