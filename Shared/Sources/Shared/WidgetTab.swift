import Foundation

/// Какая вкладка сейчас показана в плитке. Общая для всех размещённых копий
/// виджета — без Xcode нет `appintentsmetadataprocessor`, а значит нет и
/// `AppIntentConfiguration`, которая нужна для per-instance конфигурации
/// (когда у каждой копии виджета на столе свой независимый выбор). Поэтому
/// вкладка одна на все копии сразу, хранится в UserDefaults у Host и
/// публикуется вместе со снепшотом.
public enum WidgetTab: String, Codable, CaseIterable {
    case both
    case claude
    case codex
}
