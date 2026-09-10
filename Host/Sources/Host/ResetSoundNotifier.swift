import Foundation
import Shared

/// Проигрывает системный звук в момент, когда 5-часовой лимит сбрасывается.
/// Состояние (последний `resetsAt`/`usedPercent`) живёт в UserDefaults,
/// отдельно от порогов `UsageNotifier` и от `LimitReachedNotifier`, чтобы не
/// путать три разных события (приближение к лимиту / сам сброс / достижение 100%).
///
/// Сброс окна фиксируем только если ОБА условия верны — иначе дребезг API
/// (например, сервер чуть пересчитал `resetsAt` без реального нового окна)
/// даст ложное срабатывание:
/// 1. время сброса реально сдвинулось вперёд больше чем на 60 секунд;
/// 2. процент использования при этом упал (а не остался прежним/вырос).
enum ResetSoundNotifier {
    static func check(key: String, window: UsageWindow?) {
        guard let window, let resetsAt = window.resetsAt else { return }

        let defaults = UserDefaults.standard
        let resetKey = "\(key).soundResetsAt"
        let usedKey = "\(key).soundUsedPercent"

        let newResetsAt = resetsAt.timeIntervalSince1970
        let newUsed = window.usedPercent
        let oldResetsAt = defaults.object(forKey: resetKey) as? Double
        let oldUsed = defaults.object(forKey: usedKey) as? Double

        defaults.set(newResetsAt, forKey: resetKey)
        defaults.set(newUsed, forKey: usedKey)

        guard let oldResetsAt, let oldUsed, oldUsed > 0 else { return }
        let rolled = newResetsAt > oldResetsAt + 60
        let droppedUsage = newUsed <= oldUsed + 0.5
        guard rolled, droppedUsage else { return }

        guard defaults.bool(forKey: "resetSoundEnabled") else { return }
        let name = defaults.string(forKey: "resetSoundName") ?? SystemSoundOption.glass.rawValue
        SystemSoundPlayer.play(name)
    }
}
