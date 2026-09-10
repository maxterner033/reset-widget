import Foundation
import UserNotifications
import Shared

/// Локальные уведомления при приближении к лимиту (5ч/недельному).
/// Разрешение спрашивается один раз при первом вызове `requestAuthorizationIfNeeded()`.
/// Состояние (какой порог уже прислали для текущего окна) живёт в UserDefaults,
/// чтобы не спамить каждые 5 минут, и сбрасывается сам, когда `resetsAt` меняется
/// (значит, окно уже сброшено и открылось новое).
enum UsageNotifier {
    /// Пороги по остатку (%), от которых предупреждаем. Идут по убыванию.
    private static let thresholds: [(level: Int, remainingBelow: Double)] = [
        (2, 5),
        (1, 20)
    ]

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    HostMain.log("→ уведомления: не удалось запросить разрешение — \(error.localizedDescription)")
                } else {
                    HostMain.log("→ уведомления: разрешение \(granted ? "выдано" : "отклонено")")
                }
            }
        }
    }

    static func check(providerLabel: String, windowLabel: String, key: String, window: UsageWindow?) {
        guard let window else { return }
        let remaining = 100 - window.usedPercent
        let resetKey = "\(key).resetsAt"
        let tierKey = "\(key).notifiedTier"
        let defaults = UserDefaults.standard

        let resetsAtStamp = window.resetsAt.map { String($0.timeIntervalSince1970) } ?? "unknown"
        if defaults.string(forKey: resetKey) != resetsAtStamp {
            defaults.set(resetsAtStamp, forKey: resetKey)
            defaults.set(0, forKey: tierKey)
        }

        let alreadyNotifiedTier = defaults.integer(forKey: tierKey)
        guard let hit = thresholds.first(where: { remaining < $0.remainingBelow && $0.level > alreadyNotifiedTier }) else {
            return
        }

        defaults.set(hit.level, forKey: tierKey)
        send(
            title: "\(providerLabel): осталось \(Int(remaining))%",
            body: "Лимит \(windowLabel) почти исчерпан."
        )
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                HostMain.log("→ уведомления: не удалось отправить — \(error.localizedDescription)")
            }
        }
    }
}
