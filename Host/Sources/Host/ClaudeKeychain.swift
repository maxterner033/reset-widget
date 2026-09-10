import Foundation
import Security

/// Читает credential blob, который `claude login` кладёт в Keychain
/// под сервисом "Claude Code-credentials". Первое обращение из нового
/// бинарника вызовет системный диалог macOS — после "Always Allow"
/// дальнейшие чтения проходят без вопросов.
enum ClaudeKeychainError: Error, LocalizedError {
    case notFound
    case status(OSStatus)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "В Keychain нет записи \"Claude Code-credentials\". Выполни `claude login`."
        case .status(let s):
            return "Keychain вернул статус \(s) (\(SecCopyErrorMessageString(s, nil) as String? ?? "unknown"))."
        case .decodeFailed(let m):
            return "Не удалось разобрать credential blob: \(m)"
        }
    }
}

struct ClaudeCredentials {
    let accessToken: String
    let subscriptionType: String?
}

enum ClaudeKeychain {
    static func load() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw ClaudeKeychainError.notFound }
        guard status == errSecSuccess else { throw ClaudeKeychainError.status(status) }
        guard let data = result as? Data else {
            throw ClaudeKeychainError.decodeFailed("keychain вернул не Data")
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeKeychainError.decodeFailed("payload не JSON")
        }
        // Claude Code хранит токен под ключом "claudeAiOauth"; на всякий случай
        // допускаем и вариант без обёртки.
        let inner = (raw["claudeAiOauth"] as? [String: Any]) ?? raw
        guard let token = inner["accessToken"] as? String, !token.isEmpty else {
            throw ClaudeKeychainError.decodeFailed("нет accessToken; ключи=\(Array(inner.keys).sorted())")
        }
        let subscription = inner["subscriptionType"] as? String
        return ClaudeCredentials(accessToken: token, subscriptionType: subscription)
    }
}
