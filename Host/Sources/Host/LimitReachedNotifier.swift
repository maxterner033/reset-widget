import Foundation
import Shared

/// Звук, когда любой лимит (5ч или недельный, Claude или Codex) доходит до
/// 100% использования. В отличие от `ResetSoundNotifier`, состояние "уже был
/// на 100%" хранится персистентно и не завязано на baseline первого запуска —
/// если лимит был исчерпан, пока host не работал, звук всё равно прозвучит на
/// первом же успешном чтении после запуска. Неудачное чтение (window == nil)
/// не трогает сохранённое состояние — иначе временный сбой сети сбросил бы
/// флаг и следующее успешное чтение зря переобъявило бы уже известный "потолок".
enum LimitReachedNotifier {
    static func check(key: String, window: UsageWindow?) {
        guard let window else { return }

        let defaults = UserDefaults.standard
        let reachedKey = "\(key).reached"
        let isReached = window.usedPercent >= 99.5
        let wasReached = defaults.bool(forKey: reachedKey)
        defaults.set(isReached, forKey: reachedKey)

        guard isReached, !wasReached else { return }
        guard defaults.bool(forKey: "limitReachedSoundEnabled") else { return }
        let name = defaults.string(forKey: "limitReachedSoundName") ?? SystemSoundOption.sosumi.rawValue
        SystemSoundPlayer.play(name)
    }
}
