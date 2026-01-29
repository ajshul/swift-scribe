import SwiftUI

enum ThemeOption: CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func from(colorScheme: ColorScheme?) -> ThemeOption {
        switch colorScheme {
        case .light: return .light
        case .dark: return .dark
        case .none: return .system
        case .some(_): return .system
        }
    }
}

#if os(macOS)
    struct SettingsView: View {
        @Bindable var settings: AppSettings
        @State private var selectedTheme: ThemeOption = .system

        var body: some View {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(ThemeOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .onChange(of: selectedTheme) { _, newValue in
                        settings.setColorScheme(newValue.colorScheme)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 400, minHeight: 200)
            .onAppear {
                selectedTheme = ThemeOption.from(colorScheme: settings.colorScheme)
            }
        }
    }
#endif
