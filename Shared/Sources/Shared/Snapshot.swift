import Foundation

/// Один лимит с процентом использования и временем сброса.
public struct UsageWindow: Codable, Equatable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Данные по одному провайдеру (Claude Code или Codex).
public struct ProviderUsage: Codable, Equatable {
    public let session: UsageWindow?
    public let weekly: UsageWindow?
    public let planLabel: String?
    public let errorMessage: String?
    /// true, если провайдер не залогинен/не установлен (а не временная
    /// ошибка сети) — такую строку виджет прячет вместо показа "ошибка".
    public let notConfigured: Bool
    /// true, если токен/сессия протухли настолько, что нужен повторный
    /// логин (HTTP 401/403) — отличается от временной ошибки сети/сервера:
    /// виджет показывает "вход истёк" вместо общего "ошибка".
    public let authExpired: Bool
    /// true, если Host не смог прочитать токен без диалога Keychain: владелец
    /// записи (Claude Code) переписал её и сбросил разрешения. Виджет
    /// показывает "нужен доступ" — ссылку, по клику на которую Host читает
    /// запись уже с диалогом. Так диалог появляется по действию пользователя,
    /// а не внезапно посреди работы.
    public let accessRequired: Bool

    public init(
        session: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        planLabel: String? = nil,
        errorMessage: String? = nil,
        notConfigured: Bool = false,
        authExpired: Bool = false,
        accessRequired: Bool = false
    ) {
        self.session = session
        self.weekly = weekly
        self.planLabel = planLabel
        self.errorMessage = errorMessage
        self.notConfigured = notConfigured
        self.authExpired = authExpired
        self.accessRequired = accessRequired
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decodeIfPresent(UsageWindow.self, forKey: .session)
        weekly = try c.decodeIfPresent(UsageWindow.self, forKey: .weekly)
        planLabel = try c.decodeIfPresent(String.self, forKey: .planLabel)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        notConfigured = try c.decodeIfPresent(Bool.self, forKey: .notConfigured) ?? false
        authExpired = try c.decodeIfPresent(Bool.self, forKey: .authExpired) ?? false
        accessRequired = try c.decodeIfPresent(Bool.self, forKey: .accessRequired) ?? false
    }
}

/// Снепшот, который Host пишет в контейнер виджета, а виджет читает.
public struct Snapshot: Codable, Equatable {
    public let generatedAt: Date
    public let claude: ProviderUsage?
    public let codex: ProviderUsage?
    public let selectedTab: WidgetTab

    public init(generatedAt: Date, claude: ProviderUsage?, codex: ProviderUsage?, selectedTab: WidgetTab = .both) {
        self.generatedAt = generatedAt
        self.claude = claude
        self.codex = codex
        self.selectedTab = selectedTab
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        claude = try c.decodeIfPresent(ProviderUsage.self, forKey: .claude)
        codex = try c.decodeIfPresent(ProviderUsage.self, forKey: .codex)
        selectedTab = try c.decodeIfPresent(WidgetTab.self, forKey: .selectedTab) ?? .both
    }
}
