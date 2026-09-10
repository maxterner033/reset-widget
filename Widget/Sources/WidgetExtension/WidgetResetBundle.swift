import WidgetKit
import SwiftUI

struct WidgetResetWidget: Widget {
    static let kind = "WidgetResetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WidgetResetProvider()) { entry in
            WidgetResetView(entry: entry)
        }
        .configurationDisplayName("Reset Widget")
        .description("Лимиты Claude Code и Codex")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct WidgetResetBundle: WidgetBundle {
    var body: some Widget {
        WidgetResetWidget()
    }
}
