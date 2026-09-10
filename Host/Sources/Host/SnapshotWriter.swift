import Foundation
import Shared

/// Host не в sandbox, поэтому может писать напрямую в контейнер виджета —
/// App Groups не нужны. При первом обращении к чужому контейнеру macOS
/// может один раз спросить разрешение; дальше пишет молча.
enum SnapshotWriter {
    private static let widgetBundleID = "dev.maxterner.WidgetReset.Widget"

    private static var widgetAppSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support")
    }

    /// Атомарная запись: сначала во временный файл рядом, потом rename —
    /// виджет никогда не увидит частично записанный JSON.
    static func write(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        let dir = widgetAppSupportURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let finalURL = dir.appendingPathComponent("snapshot.json")
        let tmpURL = dir.appendingPathComponent("snapshot.json.tmp-\(UUID().uuidString)")

        try data.write(to: tmpURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(finalURL, withItemAt: tmpURL)
    }
}
