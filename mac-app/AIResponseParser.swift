import Foundation

enum AIResponseParser {
    static func responseText(from json: [String: Any]?, provider: String) -> String? {
        guard let json else { return nil }
        if provider == "claude" {
            guard let content = json["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { block in
                block["text"] as? String
            }.joined()
        }

        if let outputText = json["output_text"] as? String {
            return outputText
        }
        if let output = json["output"] as? [[String: Any]] {
            let text = output.compactMap { item -> String? in
                guard let content = item["content"] as? [[String: Any]] else { return nil }
                return content.compactMap { block in
                    (block["text"] as? String) ?? (block["content"] as? String)
                }.joined()
            }.joined()
            if !text.isEmpty {
                return text
            }
        }

        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            return nil
        }
        return content
    }

    static func deltaText(fromStreamLine line: String, provider: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonString: String
        if trimmed.hasPrefix("data:") {
            jsonString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            jsonString = trimmed
        }
        if jsonString == "[DONE]" { return nil }
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let type = json["type"] as? String, type == "response.output_text.delta" {
            return json["delta"] as? String
        }
        if let type = json["type"] as? String, type == "response.completed" {
            return nil
        }

        if let choices = json["choices"] as? [[String: Any]], let first = choices.first {
            if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
                return content
            }
            if let delta = first["delta"] as? [String: Any],
               delta["reasoning_content"] as? String != nil {
                return nil
            }
            if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
                return content
            }
            if let message = first["message"] as? [String: Any],
               message["reasoning_content"] as? String != nil {
                return nil
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if provider == "claude",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return text
        }

        if json["reasoning_content"] as? String != nil {
            return nil
        }
        if let content = json["content"] as? String {
            return content
        }
        return nil
    }
}
