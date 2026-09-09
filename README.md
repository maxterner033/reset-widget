# Reset Widget

Мак-виджет: 5-часовые (session) лимиты Claude Code и Codex прямо на рабочем столе / в сайдборе виджетов — без захода в CLI, без App Groups, без Apple Developer Program.

## Статус

Планирование завершено, реализация не начата. Живой роадмап (риски, фазы, чек-листы) —
здесь: https://claude.ai/code/artifact/f1f3fcd5-bbc3-40bf-bc65-406ebd0c36db

Ключевые решения:
- Host-агент (`LSUIElement`, без sandbox, автозапуск через `SMAppService`) сам читает Keychain (Claude Code) и говорит с `codex app-server` (Codex), сам считает проценты и время сброса.
- Виджет — чистый читатель JSON-снепшота из своего контейнера. Никаких токенов и сетевых запросов внутри виджета.
- Сборка — `swiftc` + `codesign -s -` (ad-hoc, без Team/Apple ID), без полноценного Xcode-проекта — снимает проблему 7-дневного provisioning-профиля.

## Структура (план)

```
Host/      — фоновый агент: чтение Keychain/auth.json, опрос лимитов, запись снепшота
Widget/    — WidgetKit-расширение: TimelineProvider + SwiftUI-вёрстка
Shared/    — общая Codable-схема snapshot.json
docs/      — черновики ТЗ и справочные материалы
```

## Docs

- `docs/spec.md` — рабочий черновик ТЗ (архитектура, обходы ограничений, референсы).
