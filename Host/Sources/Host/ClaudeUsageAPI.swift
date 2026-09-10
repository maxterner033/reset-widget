import Foundation
import Shared

/// Дёргает тот же эндпоинт, что использует `/status` в самом Claude Code CLI.
enum ClaudeUsageAPIError: Error, LocalizedError {
    case unauthorized
    case http(Int, String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Сессия истекла (HTTP 401/403). Выполни `claude` → `/login`."
        case .http(let code, let body):
            return "api.anthropic.com вернул HTTP \(code): \(body.prefix(200))"
        case .parseFailed(let m):
            return "Не удалось разобрать ответ usage API: \(m)"
        }
    }
}

enum ClaudeUsageAPI {
    private static let usageURL = URL(string: "https://api.anthropic.com/oauth/usage")!

    static func fetch(accessToken: String) async throws -> ProviderUsage {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("claude-code", forHTTPHeaderField: "user-agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeUsageAPIError.http(0, "нет HTTPURLResponse")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClaudeUsageAPIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeUsageAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageAPIError.parseFailed("корень ответа не JSON-объект")
        }

        return ProviderUsage(
            session: usageWindow(raw["five_hour"]),
            weekly: usageWindow(raw["seven_day"]),
            planLabel: nil,
            errorMessage: nil
        )
    }

    private static func usageWindow(_ any: Any?) -> UsageWindow? {
        guard let dict = any as? [String: Any] else { return nil }
        let percent: Double
        if let d = dict["utilization"] as? Double {
            percent = d
        } else if let i = dict["utilization"] as? Int {
            percent = Double(i)
        } else {
            percent = 0
        }
        let resets = (dict["resets_at"] as? String).flatMap(parseISODate)
        return UsageWindow(usedPercent: percent, resetsAt: resets)
    }

    private static func parseISODate(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: s) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
