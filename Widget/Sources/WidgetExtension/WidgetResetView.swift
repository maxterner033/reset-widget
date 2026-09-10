import SwiftUI
import Shared

struct WidgetResetView: View {
    var entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var currentTab: WidgetTab {
        entry.snapshot?.selectedTab ?? .both
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                // Системные отступы отключены целиком ради пиксельной вёрстки
                // medium — small получает их обратно вручную и остаётся прежним.
                smallLayout.padding(contentMargins)
            default:
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || vibrant {
                Rectangle().fill(.fill.tertiary)
            } else {
                cardBackground
            }
        }
    }

    // MARK: - systemSmall (не трогаем — старая вёрстка до редизайна)

    private var smallLayout: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                legacyTabBar
                Group {
                    switch currentTab {
                    case .both:
                        legacyProviderBlock(label: "Claude", usage: entry.snapshot?.claude)
                        legacyProviderBlock(label: "Codex", usage: entry.snapshot?.codex)
                    case .claude:
                        legacyProviderBlock(label: "Claude", usage: entry.snapshot?.claude)
                    case .codex:
                        legacyProviderBlock(label: "Codex", usage: entry.snapshot?.codex)
                    }
                }
                if visibleProviders.isEmpty {
                    Text(emptyStateMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Link(destination: URL(string: "widgetreset://settings")!) {
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private var legacyTabBar: some View {
        HStack(spacing: 10) {
            legacyTabLink(title: "Оба", tab: .both)
            legacyTabLink(title: "Claude", tab: .claude)
            legacyTabLink(title: "Codex", tab: .codex)
        }
    }

    private func legacyTabLink(title: String, tab: WidgetTab) -> some View {
        Link(destination: URL(string: "widgetreset://\(tab.rawValue)")!) {
            Text(title)
                .font(.caption2)
                .fontWeight(currentTab == tab ? .bold : .regular)
                .foregroundStyle(currentTab == tab ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private func legacyProviderBlock(label: String, usage: ProviderUsage?) -> some View {
        if usage?.notConfigured != true {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label).font(.caption).bold()
                    Spacer()
                    if usage?.authExpired == true {
                        Text("вход истёк").font(.caption2).foregroundStyle(.red)
                    } else if usage?.errorMessage != nil {
                        Text("ошибка").font(.caption2).foregroundStyle(.red)
                    }
                }
                legacyUsageBar(title: "5ч", window: usage?.session)
                legacyUsageBar(title: "Нед", window: usage?.weekly)
            }
        }
    }

    @ViewBuilder
    private func legacyUsageBar(title: String, window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            GeometryReader { geo in
                let remaining = 100 - min(max(window?.usedPercent ?? 0, 0), 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if window != nil {
                        Capsule()
                            .fill(barColor(forRemaining: remaining))
                            .frame(width: geo.size.width * CGFloat(remaining) / 100)
                    }
                }
            }
            .frame(height: 6)
            Text(window.map { "\(Int(100 - $0.usedPercent))%" } ?? "—")
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - systemMedium — макет из Claude Design (338×158pt)

    /// Палитра макета. Работает только в `.fullColor`, где мы сами рисуем
    /// светлую карточку: там фон известен, поэтому цвета фиксированные.
    private enum Palette {
        static let ink = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
        static let track = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255).opacity(0.28)
        static let shadow = Color(red: 60 / 255, green: 50 / 255, blue: 90 / 255)

        static func label(_ opacity: Double) -> Color {
            Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(opacity)
        }
    }

    /// В стиле виджетов "Автоматически" система рендерит плитку в `.vibrant`:
    /// обесцвечивает содержимое и подкладывает фон, вытянутый из обоев. Наш
    /// светлый фон туда не доезжает, а фиксированный тёмный текст сливается с
    /// тёмной подложкой. Поэтому в этом режиме — только иерархические стили:
    /// они сами дают белый по тёмному и тёмный по светлому.
    private var vibrant: Bool { renderingMode == .vibrant }

    private enum Tier { case primary, secondary, tertiary, quaternary }

    private func fg(_ tier: Tier) -> AnyShapeStyle {
        guard !vibrant else {
            switch tier {
            case .primary: return AnyShapeStyle(.primary)
            case .secondary: return AnyShapeStyle(.secondary)
            case .tertiary: return AnyShapeStyle(.tertiary)
            case .quaternary: return AnyShapeStyle(.quaternary)
            }
        }
        switch tier {
        case .primary: return AnyShapeStyle(Palette.ink)
        case .secondary: return AnyShapeStyle(Palette.label(0.62))
        case .tertiary: return AnyShapeStyle(Palette.label(0.45))
        case .quaternary: return AnyShapeStyle(Palette.label(0.18))
        }
    }

    private struct ProviderSlot {
        let name: String
        let usage: ProviderUsage?
    }

    private var visibleProviders: [ProviderSlot] {
        let all = [
            ProviderSlot(name: "Claude", usage: entry.snapshot?.claude),
            ProviderSlot(name: "Codex", usage: entry.snapshot?.codex)
        ]
        let configured = all.filter { $0.usage != nil && $0.usage?.notConfigured != true }
        switch currentTab {
        case .both: return configured
        case .claude: return configured.filter { $0.name == "Claude" }
        case .codex: return configured.filter { $0.name == "Codex" }
        }
    }

    private var mediumLayout: some View {
        VStack(spacing: 0) {
            tabPill

            Group {
                if visibleProviders.isEmpty {
                    Text(emptyStateMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(fg(.secondary))
                        .multilineTextAlignment(.center)
                } else if currentTab == .both {
                    combinedBlocks
                } else if let slot = visibleProviders.first {
                    singleBlock(slot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(fg(.quaternary))
                .frame(height: 1)
                .padding(.bottom, 7)

            footRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tabPill: some View {
        HStack(spacing: 0) {
            pillTab(title: "Claude/Codex", tab: .both)
            pillDivider
            pillTab(title: "Claude", tab: .claude)
            pillDivider
            pillTab(title: "Codex", tab: .codex)
        }
        .padding(4)
        .background(pillFill, in: Capsule())
        .shadow(color: vibrant ? .clear : Palette.shadow.opacity(0.12), radius: 3, y: 2)
    }

    /// Белая капсула держится только на своём светлом фоне; в vibrant система
    /// красит её вместе со всем остальным, поэтому там — системная заливка.
    private var pillFill: AnyShapeStyle {
        vibrant ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(Color.white.opacity(0.82))
    }

    private var pillDivider: some View {
        Rectangle()
            .fill(fg(.quaternary))
            .frame(width: 1, height: 13)
    }

    private func pillTab(title: String, tab: WidgetTab) -> some View {
        Link(destination: URL(string: "widgetreset://\(tab.rawValue)")!) {
            Text(title)
                .font(.system(size: 13, weight: currentTab == tab ? .bold : .medium))
                .tracking(-0.1)
                .foregroundStyle(fg(currentTab == tab ? .primary : .tertiary))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .contentShape(Capsule())
        }
    }

    private func singleBlock(_ slot: ProviderSlot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(slot.name)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(fg(.primary))
                Spacer()
                statusLabel(for: slot.usage, size: 11)
            }
            .padding(.bottom, 1)
            usageRow(title: "5ч", window: slot.usage?.session, compact: false)
            usageRow(title: "Нед", window: slot.usage?.weekly, compact: false)
        }
        .padding(.top, 4)
    }

    /// Во вкладке "Оба" провайдеры стоят двумя колонками через разделитель —
    /// так обе пары баров помещаются, не наезжая на овал вкладок и футер.
    private var combinedBlocks: some View {
        HStack(spacing: 12) {
            ForEach(Array(visibleProviders.enumerated()), id: \.element.name) { item in
                if item.offset > 0 {
                    Rectangle()
                        .fill(fg(.quaternary))
                        .frame(width: 1, height: 52)
                }
                compactBlock(item.element)
            }
        }
        .padding(.top, 6)
    }

    private func compactBlock(_ slot: ProviderSlot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(slot.name)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(fg(.primary))
                Spacer()
                statusLabel(for: slot.usage, size: 10)
            }
            usageRow(title: "5ч", window: slot.usage?.session, compact: true)
            usageRow(title: "Нед", window: slot.usage?.weekly, compact: true)
        }
        .frame(maxWidth: .infinity)
    }

    /// Ошибка/протухший вход занимают место подписи тарифа — отдельного слота
    /// под них в макете нет, а одновременно с тарифом они не нужны.
    @ViewBuilder
    private func statusLabel(for usage: ProviderUsage?, size: CGFloat) -> some View {
        if usage?.authExpired == true {
            statusText("ВХОД ИСТЁК", size: size, style: alarmStyle)
        } else if usage?.errorMessage != nil {
            statusText("ОШИБКА", size: size, style: alarmStyle)
        } else if let plan = usage?.planLabel {
            statusText(plan.uppercased(), size: size, style: fg(.tertiary))
        }
    }

    /// В vibrant красный обесцвечивается до того же серого, что и подпись
    /// тарифа, — там тревожное состояние отличается не цветом, а контрастом.
    private var alarmStyle: AnyShapeStyle {
        vibrant ? fg(.primary) : AnyShapeStyle(Color.red)
    }

    private func statusText(_ text: String, size: CGFloat, style: AnyShapeStyle) -> some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(style)
    }

    private func usageRow(title: String, window: UsageWindow?, compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(fg(.secondary))
                .frame(width: compact ? 28 : 34, alignment: .leading)

            GeometryReader { geo in
                let remaining = 100 - min(max(window?.usedPercent ?? 0, 0), 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(vibrant ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Palette.track))
                    if window != nil {
                        Capsule()
                            .fill(barFill(forRemaining: remaining))
                            .frame(width: geo.size.width * CGFloat(remaining) / 100)
                    }
                    // Засечки светлые — в vibrant они сливались бы с такой же
                    // светлой заливкой, поэтому там их просто нет.
                    if !vibrant {
                        ForEach(compact ? [0.5] : [1.0 / 3.0, 2.0 / 3.0], id: \.self) { mark in
                            Rectangle()
                                .fill(Color.white.opacity(0.55))
                                .frame(width: 1)
                                .offset(x: geo.size.width * mark)
                        }
                    }
                }
            }
            .frame(height: compact ? 8 : 9)

            Text(window.map { "\(Int((100 - $0.usedPercent).rounded()))%" } ?? "—")
                .font(.system(size: compact ? 12 : 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(fg(.primary))
                .frame(width: compact ? 34 : 40, alignment: .trailing)

            if !compact {
                Text(window.flatMap { resetLabel(for: $0.resetsAt) } ?? "")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(fg(.tertiary))
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .frame(height: compact ? 16 : 20)
    }

    private var footRow: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "widgetreset://settings")!) {
                Text("MORE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(fg(.primary))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(vibrant ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(Color.white), in: Capsule())
                    .shadow(color: vibrant ? .clear : Palette.shadow.opacity(0.16), radius: 2, y: 1)
            }
            Spacer()
            Text(lastUpdateLabel)
                .font(.system(size: 11))
                .foregroundStyle(fg(.tertiary))
        }
    }

    /// WidgetKit рендерит плитку офф-скрин, без доступа к обоям — настоящего
    /// блюра стола отсюда не получить (см. docs/spec.md), поэтому фон
    /// нарисован явным градиентом с бликом по верхнему краю.
    private var cardBackground: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 223 / 255, green: 230 / 255, blue: 245 / 255), location: 0),
                .init(color: Color(red: 230 / 255, green: 227 / 255, blue: 242 / 255), location: 0.45),
                .init(color: Color(red: 240 / 255, green: 226 / 255, blue: 236 / 255), location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.7), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Общее

    /// 0–25% ост. — красный, 25–50 — оранжевый, 50–75 — жёлтый, 75–100 — зелёный.
    private func barColor(forRemaining remaining: Double) -> Color {
        switch remaining {
        case ..<25: return .red
        case ..<50: return .orange
        case ..<75: return .yellow
        default: return .green
        }
    }

    /// В vibrant цвета недоступны — система сводит плитку к монохрому, и все
    /// четыре зоны стали бы одним оттенком. Единственный оставшийся канал —
    /// яркость, поэтому там та же шкала кодируется насыщенностью заливки:
    /// чем меньше остаток, тем заметнее полоска.
    private func barFill(forRemaining remaining: Double) -> AnyShapeStyle {
        guard vibrant else { return AnyShapeStyle(barColor(forRemaining: remaining)) }
        let level: Double
        switch remaining {
        case ..<25: level = 1.0
        case ..<50: level = 0.85
        case ..<75: level = 0.7
        default: level = 0.55
        }
        return AnyShapeStyle(HierarchicalShapeStyle.primary.opacity(level))
    }

    private var emptyStateMessage: String {
        entry.snapshot == nil
            ? "Нет данных — host ещё не писал снепшот"
            : "Провайдер не настроен"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var lastUpdateLabel: String {
        let date = entry.snapshot?.generatedAt ?? entry.date
        return "Обновлено в \(Self.timeFormatter.string(from: date))"
    }

    /// "3д" / "2ч14м" / "45м" до сброса окна; nil, если время уже прошло или
    /// неизвестно. Недельное окно без переключения на дни давало "52ч14м" —
    /// не влезало в колонку, рассчитанную по макету на пять знаков.
    private func resetLabel(for resetsAt: Date?) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(entry.date)
        guard interval > 0 else { return nil }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        if hours >= 24 { return "\(hours / 24)д" }
        return hours > 0 ? "\(hours)ч\(totalMinutes % 60)м" : "\(totalMinutes)м"
    }
}
