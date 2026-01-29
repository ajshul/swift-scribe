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
                        HStack {
                            Label("Notion Integration", systemImage: "link")
                            Spacer()
                            if NotionSettings.shared.isConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
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

// MARK: - Notion Settings

@Observable
final class NotionSettings {
    static let shared = NotionSettings()

    private let tokenKey = "notion-token"
    private let databaseIdKey = "notion-database-id"
    private let autoSyncKey = "notion-auto-sync"

    var integrationToken: String {
        didSet {
            try? KeychainHelper.save(integrationToken, forKey: tokenKey)
        }
    }

    var databaseId: String {
        didSet {
            UserDefaults.standard.set(databaseId, forKey: databaseIdKey)
        }
    }

    var autoSync: Bool {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: autoSyncKey)
        }
    }

    var isConfigured: Bool {
        !integrationToken.isEmpty && !databaseId.isEmpty
    }

    private init() {
        self.integrationToken = (try? KeychainHelper.loadString(forKey: tokenKey)) ?? ""
        self.databaseId = UserDefaults.standard.string(forKey: databaseIdKey) ?? ""
        self.autoSync = UserDefaults.standard.bool(forKey: autoSyncKey)
    }

    func clearCredentials() {
        try? KeychainHelper.delete(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: databaseIdKey)
        integrationToken = ""
        databaseId = ""
    }
}

struct NotionSettingsView: View {
    @Bindable private var notionSettings = NotionSettings.shared
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                SecureField("Integration Token", text: $notionSettings.integrationToken)
                    .textContentType(.password)
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif

                TextField("Database ID", text: $notionSettings.databaseId)
                    .textContentType(.none)
                    #if os(iOS)
                        .autocapitalization(.none)
                    #endif

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(notionSettings.integrationToken.isEmpty || notionSettings.databaseId.isEmpty || isTesting)

                if let result = testResult {
                    switch result {
                    case .success:
                        Label("Connection successful", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .failure(let message):
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            } header: {
                Text("Notion API")
            } footer: {
                Text("Create an integration at notion.so/my-integrations and share your database with it.")
            }

            Section {
                Toggle("Auto-sync after recording", isOn: $notionSettings.autoSync)
            } header: {
                Text("Sync Behavior")
            } footer: {
                Text("When enabled, notes will automatically sync to Notion after transcription and summarization complete.")
            }

            Section {
                Button("Clear Notion Credentials", role: .destructive) {
                    notionSettings.clearCredentials()
                    testResult = nil
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

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                try await NotionService.shared.testConnection()
                await MainActor.run {
                    testResult = .success
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}
