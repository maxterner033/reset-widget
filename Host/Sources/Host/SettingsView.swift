import SwiftUI

/// Короткий системный звук на выбор — играется через `NSSound(named:)`,
/// имена соответствуют встроенным в macOS файлам из /System/Library/Sounds.
enum SystemSoundOption: String, CaseIterable, Identifiable {
    case glass = "Glass"
    case ping = "Ping"
    case pop = "Pop"
    case hero = "Hero"
    case sosumi = "Sosumi"
    case tink = "Tink"

    var id: String { rawValue }
}

/// Настройки MORE-панели, открываемой по ссылке из плитки виджета.
/// Кастомный звук из файла — на будущее, пока только выбор из системных.
struct SettingsView: View {
    @AppStorage("resetSoundEnabled") private var resetEnabled = true
    @AppStorage("resetSoundName") private var resetSoundName = SystemSoundOption.glass.rawValue
    @AppStorage("limitReachedSoundEnabled") private var reachedEnabled = true
    @AppStorage("limitReachedSoundName") private var reachedSoundName = SystemSoundOption.sosumi.rawValue

    var body: some View {
        Form {
            Section("Сброс лимита") {
                Toggle("Звук при сбросе 5-часового лимита", isOn: $resetEnabled)
                soundPicker(selection: $resetSoundName)
                    .disabled(!resetEnabled)
            }
            Section("Лимит достигнут") {
                Toggle("Звук, когда любой лимит доходит до 100%", isOn: $reachedEnabled)
                soundPicker(selection: $reachedSoundName)
                    .disabled(!reachedEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 300)
    }

    private func soundPicker(selection: Binding<String>) -> some View {
        Picker("Звук", selection: selection) {
            ForEach(SystemSoundOption.allCases) { option in
                Text(option.rawValue).tag(option.rawValue)
            }
        }
        .onChange(of: selection.wrappedValue) { _, newValue in
            SystemSoundPlayer.play(newValue)
        }
    }
}
