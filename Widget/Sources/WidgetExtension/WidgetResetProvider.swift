import WidgetKit
import Shared
import Foundation

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

/// Виджет ничего не запрашивает сам — только читает готовый снепшот,
/// который в свой контейнер (Application Support внутри песочницы
/// расширения) кладёт несигнированный Host-агент.
struct WidgetResetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: Self.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: Self.loadSnapshot())
        let nextReload = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextReload)))
    }

    static func loadSnapshot() -> Snapshot? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }

        let url = appSupport.appendingPathComponent("snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
