import Foundation

enum AIRequestErrorText {
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()
        let domain = nsError.domain.lowercased()

        if nsError.code == -10 || description.contains("missing api key") {
            return AppText.localized(
                "还没有配置当前模型的 API Key。请先打开设置，选择模型并填写 API Key。",
                "The current model does not have an API Key yet. Open Settings, choose a model, and enter the API Key."
            )
        }

        if nsError.domain == NSURLErrorDomain {
            return networkMessage(for: nsError)
        }

        if isLocalProvider(domain: domain, description: description) {
            return localServiceMessage(for: nsError, description: description)
        }

        if isAuthorizationFailure(code: nsError.code, description: description) {
            return AppText.localized(
                "API Key 无效、权限不足，或当前模型不允许访问。请在设置里检查 API Key 和所选模型。",
                "The API Key is invalid, lacks permission, or cannot access the selected model. Check the API Key and selected model in Settings."
            )
        }

        if nsError.code == 402 || containsAny(description, ["insufficient quota", "billing", "balance", "quota exceeded"]) {
            return AppText.localized(
                "账户余额不足、计费不可用，或额度已用完。请检查对应模型服务账户。",
                "The account balance, billing, or quota is unavailable. Check the account for this model service."
            )
        }

        if nsError.code == 404 || containsAny(description, ["model_not_found", "model not found", "not found"]) {
            return AppText.localized(
                "当前模型或接口地址不可用。请在设置里检查模型 ID、接口地址，或切换其他模型。",
                "The selected model or endpoint is unavailable. Check the model ID, endpoint, or switch models in Settings."
            )
        }

        if nsError.code == 429 || containsAny(description, ["rate limit", "too many requests", "rate_limit", "throttle"]) {
            return AppText.localized(
                "请求太频繁或额度已达上限。请稍后再试，或切换到其他模型。",
                "Too many requests or the quota has been reached. Try again later or switch models."
            )
        }

        if (500...599).contains(nsError.code) {
            return AppText.localized(
                "模型服务暂时异常。请稍后再试，或切换其他模型。",
                "The model service is temporarily unavailable. Try again later or switch models."
            )
        }

        if nsError.code == -2 || containsAny(description, ["unexpected response", "invalid response", "no response data"]) {
            return AppText.localized(
                "模型返回内容无法识别。请检查当前模型是否兼容聊天接口，或切换其他模型。",
                "The model response could not be recognized. Check whether the selected model supports the chat endpoint, or switch models."
            )
        }

        return AppText.localized(
            "AI 请求失败。请检查模型设置、API Key 和网络后再试。",
            "The AI request failed. Check the model settings, API Key, and network, then try again."
        )
    }

    private static func networkMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorNotConnectedToInternet:
            return AppText.localized("网络不可用。请检查网络连接后再试。", "Network is unavailable. Check your connection and try again.")
        case NSURLErrorTimedOut:
            return AppText.localized("请求超时了。请稍后再试，或切换到响应更快的模型。", "The request timed out. Try again later, or switch to a faster model.")
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return AppText.localized("找不到模型服务地址。请检查接口地址、DNS 或网络代理。", "Cannot find the model service host. Check the endpoint, DNS, or network proxy.")
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return AppText.localized("无法连接到模型服务。请检查网络，或确认当前模型服务可用。", "Cannot connect to the model service. Check your network or confirm the service is available.")
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return AppText.localized("模型服务 HTTPS 连接失败。请检查系统时间、代理或证书设置。", "The model service HTTPS connection failed. Check the system clock, proxy, or certificate settings.")
        default:
            return AppText.localized("请求模型服务失败。请检查网络、代理和 API Key 后再试。", "The model request failed. Check the network, proxy, and API Key, then try again.")
        }
    }

    private static func localServiceMessage(for error: NSError, description: String) -> String {
        if error.code == 404 || containsAny(description, ["model_not_found", "model not found", "not found"]) {
            return AppText.localized(
                "本地模型或接口地址不可用。请确认本地服务已加载该模型，并检查设置里的模型 ID。",
                "The local model or endpoint is unavailable. Confirm the local service has loaded this model and check the model ID in Settings."
            )
        }

        if error.code == -2 || containsAny(description, ["unexpected response", "invalid response", "no response data"]) {
            return AppText.localized(
                "本地服务返回内容无法识别。请确认它兼容 OpenAI 聊天接口。",
                "The local service returned an unrecognized response. Confirm it is compatible with the OpenAI chat endpoint."
            )
        }

        return AppText.localized(
            "本地模型服务暂时不可用。请确认服务已启动、接口地址正确，再重试。",
            "The local model service is unavailable. Confirm the service is running, the endpoint is correct, then try again."
        )
    }

    private static func isAuthorizationFailure(code: Int, description: String) -> Bool {
        code == 401 || code == 403 || containsAny(description, [
            "unauthorized",
            "forbidden",
            "invalid api key",
            "invalid_api_key",
            "permission",
            "access denied"
        ])
    }

    private static func isLocalProvider(domain: String, description: String) -> Bool {
        containsAny(domain, ["ollama", "local-openai"]) ||
            containsAny(description, ["127.0.0.1", "localhost", "ollama"])
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
