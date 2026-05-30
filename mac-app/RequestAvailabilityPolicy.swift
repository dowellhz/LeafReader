import Foundation

enum RequestAvailabilityPolicy {
    static func canUseSelectedModel(hasAPIKey: Bool = AISettingsStore.hasAPIKeyForSelectedModel) -> Bool {
        hasAPIKey
    }

    static func shouldUseLocalDictionaryFallback(
        for error: Error,
        isOnline: Bool = NetworkConnectivityMonitor.shared.isOnline
    ) -> Bool {
        !isOnline && NetworkConnectivityMonitor.isNetworkConnectivityError(error)
    }
}
