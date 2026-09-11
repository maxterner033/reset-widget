import Foundation
import Security

/// Читает credential blob, который `claude login` кладёт в Keychain
/// под сервисом "Claude Code-credentials".
///
/// Запись чужая: её владелец — Claude Code, и при каждом обновлении токена
/// он переписывает элемент, сбрасывая список приложений с "Always Allow".
/// Поэтому по умолчанию читаем без интерфейса: если система хочет спросить
/// разрешение, получаем ошибку вместо диалога поверх работы пользователя.
/// Диалог показываем только по явному клику в виджете (`allowUI: true`).
///
/// Проверено на macOS 15: `kSecUseAuthenticationUIFail` для legacy-связки
/// не действует (диалог всё равно появляется), работает только
/// `SecKeychainSetUserInteractionAllowed(false)` — оно и используется.
enum ClaudeKeychainError: Error, LocalizedError {
    case notFound
    /// Система хотела показать диалог разрешения, а мы это запретили,
    /// либо пользователь нажал "Deny".
    case accessRequired
    case status(OSStatus)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "В Keychain нет записи \"Claude Code-credentials\". Выполни `claude login`."
        case .accessRequired:
            return "Нужно разрешить доступ к записи Claude Code в Keychain."
        case .status(let s):
            return "Keychain вернул статус \(s) (\(SecCopyErrorMessageString(s, nil) as String? ?? "unknown"))."
        case .decodeFailed(let m):
            return "Не удалось разобрать credential blob: \(m)"
        }
    }
}

struct ClaudeCredentials: Equatable {
    let accessToken: String
    let subscriptionType: String?
}

enum ClaudeKeychain {
    /// Флаг интерактивности — глобальный для процесса, поэтому все чтения
    /// идут через одну последовательную очередь: интерактивное чтение
    /// (с диалогом) не пересекается с фоновым.
    private static let queue = DispatchQueue(label: "dev.maxterner.WidgetReset.keychain")

    static func load(allowUI: Bool) async throws -> ClaudeCredentials {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try loadSync(allowUI: allowUI) })
            }
        }
    }

    private static func loadSync(allowUI: Bool) throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        SecKeychainSetUserInteractionAllowed(allowUI)
        defer { SecKeychainSetUserInteractionAllowed(true) }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw ClaudeKeychainError.notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw ClaudeKeychainError.accessRequired
        default:
            throw ClaudeKeychainError.status(status)
        }
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
