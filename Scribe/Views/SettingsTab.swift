import SwiftUI

struct SettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedTheme: ThemeOption = .system

    var body: some View {
        NavigationStack {
            Form {
                // Notion section
                Section {
                    NavigationLink {
                        NotionSettingsView()
                    } label: {
                        Label("Notion Integration", systemImage: "link")
                    }
                } header: {
                    Text("Sync")
                }

                // Appearance section
                Section {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(ThemeOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .onChange(of: selectedTheme) { _, newValue in
                        settings.setColorScheme(newValue.colorScheme)
                    }
                } header: {
                    Text("Appearance")
                }

                // Privacy section
                Section {
                    Label {
                        Text("Transcription and summaries run entirely on-device using Apple Intelligence. No audio or text data is sent to any server for AI processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Privacy")
                }

                // About section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
            .onAppear {
                selectedTheme = ThemeOption.from(colorScheme: settings.colorScheme)
            }
        }
    }
}

// MARK: - Notion Settings Placeholder

struct NotionSettingsView: View {
    @State private var integrationToken = ""
    @State private var databaseId = ""
    @State private var autoSync = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                SecureField("Integration Token", text: $integrationToken)
                    .textContentType(.password)

                TextField("Database ID", text: $databaseId)
                    .textContentType(.none)
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif

                Button("Test Connection") {
                    // TODO: Wire NotionService test connection
                    testResult = "Not yet implemented"
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Success") ? .green : .orange)
                }
            } header: {
                Text("Notion API")
            } footer: {
                Text("Create an integration at notion.so/my-integrations and share your database with it.")
            }

            Section {
                Toggle("Auto-sync after recording", isOn: $autoSync)
            } header: {
                Text("Sync Behavior")
            } footer: {
                Text("When enabled, notes will automatically sync to Notion after transcription and summarization complete.")
            }

            Section {
                Button("Clear Notion Credentials", role: .destructive) {
                    integrationToken = ""
                    databaseId = ""
                    testResult = nil
                    // TODO: Clear Keychain
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .navigationTitle("Notion")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
