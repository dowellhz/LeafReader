import Foundation

struct AIModelConfig {
    let id: String
    let provider: String
    let displayName: String
    let endpoint: URL
    let model: String
    let supportsThinkingToggle: Bool

    var usesAzureAPIKeyHeader: Bool {
        guard provider == AISettingsStore.customProviderID,
              let host = endpoint.host?.lowercased() else {
            return false
        }
        return host.hasSuffix(".openai.azure.com")
            || host.hasSuffix(".services.ai.azure.com")
            || host.hasSuffix(".cognitiveservices.azure.com")
    }

    var usesAzureDeploymentEndpoint: Bool {
        guard usesAzureAPIKeyHeader else { return false }
        return endpoint.path.lowercased().contains("/openai/deployments/")
    }

    var usesResponsesEndpoint: Bool {
        let path = endpoint.path.lowercased()
        return path.hasSuffix("/openai/responses") || path.hasSuffix("/openai/v1/responses")
    }
}
