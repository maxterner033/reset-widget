import Foundation
import Shared
import SwiftUI
import AppKit
import WidgetKit
import ServiceManagement

@main
struct WidgetResetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Без окна: агент живёт через AppDelegate, Settings-сцена сама
        // не открывается — нужна только чтобы удовлетворить протокол App.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Host не ограничен троттлингом WidgetKit, поэтому может обновлять
    /// снепшот чаще, чем виджет реально перерисовывается.
    private let refreshInterval: Duration = .seconds(5 * 60)
    private var refreshTask: Task<Void, Never>?

    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "resetSoundEnabled": true,
            "resetSoundName": SystemSoundOption.glass.rawValue,
            "limitReachedSoundEnabled": true,
            "limitReachedSoundName": SystemSoundOption.sosumi.rawValue,
            "widgetSelectedTab": WidgetTab.both.rawValue
        ])
        registerLoginItemIfNeeded()
        UsageNotifier.requestAuthorizationIfNeeded()
        refreshTask = Task {
            while !Task.isCancelled {
                await HostMain.updateSnapshot()
                try? await Task.sleep(for: refreshInterval)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
    }

    /// Ссылки в плитке виджета открывают `widgetreset://<host>` (схема
    /// зарегистрирована в App/Info.plist) — LaunchServices запускает Host и
    /// вызывает этот делегатский метод вместо Apple Event-обвязки.
    /// `settings` открывает окно настроек; `keychain-access` — чтение записи
    /// Claude Code с системным диалогом (единственное место, где он
    /// разрешён); `both`/`claude`/`codex` — это
    /// переключение вкладки, оно не активирует и не показывает Host —
    /// просто тихо переписывает уже известные данные с новой вкладкой.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "widgetreset" {
            if url.host == "settings" {
                showSettingsWindow()
            } else if url.host == "keychain-access" {
                HostMain.requestKeychainAccess()
            } else if let tab = url.host.flatMap(WidgetTab.init(rawValue:)) {
                HostMain.applyTabChange(tab)
            }
        }
    }

    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Widget Reset — Настройки"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func registerLoginItemIfNeeded() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            HostMain.log("→ зарегистрирован автозапуск при логине")
        } catch {
            HostMain.log("→ не удалось зарегистрировать автозапуск: \(error.localizedDescription)")
        }
    }
}

enum HostMain {
    /// Последний опубликованный снепшот — переключение вкладки переиспользует
    /// уже известные данные (не дёргает Keychain/API/app-server заново),
    /// поэтому срабатывает мгновенно, а не ждёт следующего 5-минутного цикла.
    private static var lastSnapshot: Snapshot?

    /// Токен Claude, прочитанный из Keychain. Пока API его принимает, к чужой
    /// записи не прикасаемся вообще — перечитываем только после 401, когда
    /// Claude Code, вероятно, уже положил туда свежий токен.
    private static var cachedCredentials: ClaudeCredentials?

    static func log(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }

    static func currentTab() -> WidgetTab {
        WidgetTab(rawValue: UserDefaults.standard.string(forKey: "widgetSelectedTab") ?? "") ?? .both
    }

    static func applyTabChange(_ tab: WidgetTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "widgetSelectedTab")
        guard let last = lastSnapshot else { return }
        let updated = Snapshot(generatedAt: last.generatedAt, claude: last.claude, codex: last.codex, selectedTab: tab)
        publish(updated)
    }

    /// Клик по "нужен доступ" в виджете: единственный сценарий, в котором
    /// Host читает связку с интерфейсом — диалог появляется в ответ на
    /// действие пользователя, а не сам по себе.
    static func requestKeychainAccess() {
        Task { await updateSnapshot(allowKeychainUI: true) }
    }

    static func updateSnapshot(allowKeychainUI: Bool = false) async {
        async let claudeUsage = fetchClaudeUsage(allowKeychainUI: allowKeychainUI)
        async let codexUsage = fetchCodexUsage()

        let snapshot = await Snapshot(generatedAt: Date(), claude: claudeUsage, codex: codexUsage, selectedTab: currentTab())

        UsageNotifier.check(providerLabel: "Claude", windowLabel: "5ч", key: "claude.session", window: snapshot.claude?.session)
        UsageNotifier.check(providerLabel: "Claude", windowLabel: "недельный", key: "claude.weekly", window: snapshot.claude?.weekly)
        UsageNotifier.check(providerLabel: "Codex", windowLabel: "5ч", key: "codex.session", window: snapshot.codex?.session)
        UsageNotifier.check(providerLabel: "Codex", windowLabel: "недельный", key: "codex.weekly", window: snapshot.codex?.weekly)

        ResetSoundNotifier.check(key: "claude.session", window: snapshot.claude?.session)
        ResetSoundNotifier.check(key: "codex.session", window: snapshot.codex?.session)

        LimitReachedNotifier.check(key: "claude.session", window: snapshot.claude?.session)
        LimitReachedNotifier.check(key: "claude.weekly", window: snapshot.claude?.weekly)
        LimitReachedNotifier.check(key: "codex.session", window: snapshot.codex?.session)
        LimitReachedNotifier.check(key: "codex.weekly", window: snapshot.codex?.weekly)

        publish(snapshot)
    }

    private static func publish(_ snapshot: Snapshot) {
        lastSnapshot = snapshot
        do {
            try SnapshotWriter.write(snapshot)
            log("→ снепшот записан в контейнер виджета")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            log("→ ошибка записи снепшота: \(error.localizedDescription)")
        }
    }

    static func fetchClaudeUsage(allowKeychainUI: Bool = false) async -> ProviderUsage {
        do {
            let creds: ClaudeCredentials
            let fromCache = cachedCredentials != nil
            if let cached = cachedCredentials {
                creds = cached
            } else {
                log("→ читаю Keychain (\(allowKeychainUI ? "с диалогом" : "без диалога"))...")
                creds = try await ClaudeKeychain.load(allowUI: allowKeychainUI)
                cachedCredentials = creds
            }
            log("→ токен получен, зову api.anthropic.com/oauth/usage...")
            let usage: ProviderUsage
            do {
                usage = try await ClaudeUsageAPI.fetch(accessToken: creds.accessToken)
            } catch ClaudeUsageAPIError.unauthorized where fromCache {
                // Кешированный токен протух. Claude Code, скорее всего, уже
                // обновил запись — перечитываем один раз; если там тот же
                // токен, значит нужен повторный логин, а не наш кеш.
                log("→ claude: 401 на кешированном токене — перечитываю Keychain...")
                cachedCredentials = nil
                let fresh = try await ClaudeKeychain.load(allowUI: allowKeychainUI)
                guard fresh.accessToken != creds.accessToken else {
                    throw ClaudeUsageAPIError.unauthorized
                }
                cachedCredentials = fresh
                usage = try await ClaudeUsageAPI.fetch(accessToken: fresh.accessToken)
            }
            log("→ claude: ответ получен")
            return ProviderUsage(
                session: usage.session,
                weekly: usage.weekly,
                planLabel: cachedCredentials?.subscriptionType ?? creds.subscriptionType,
                errorMessage: nil
            )
        } catch ClaudeKeychainError.notFound {
            log("→ claude: не залогинен (нет записи в Keychain) — скрываю из виджета")
            return ProviderUsage(notConfigured: true)
        } catch ClaudeKeychainError.accessRequired {
            log("→ claude: Keychain требует разрешения — жду клика по \"нужен доступ\" в виджете")
            return ProviderUsage(errorMessage: "нужен доступ к Keychain", accessRequired: true)
        } catch ClaudeUsageAPIError.unauthorized {
            cachedCredentials = nil
            log("→ claude: сессия истекла (401/403) — нужен повторный `claude`/`/login`")
            return ProviderUsage(errorMessage: "вход истёк", authExpired: true)
        } catch {
            log("→ claude: ошибка — \(error.localizedDescription)")
            return ProviderUsage(errorMessage: error.localizedDescription)
        }
    }

    static func fetchCodexUsage() async -> ProviderUsage {
        do {
            log("→ зову codex app-server...")
            let usage = try await CodexAppServer.fetch()
            log("→ codex: ответ получен")
            return usage
        } catch CodexAppServerError.binaryNotFound {
            log("→ codex: бинарник не найден (не установлен/не залогинен) — скрываю из виджета")
            return ProviderUsage(notConfigured: true)
        } catch {
            log("→ codex: ошибка — \(error.localizedDescription)")
            return ProviderUsage(errorMessage: error.localizedDescription)
        }
    }
}
