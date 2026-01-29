import AuthenticationServices
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
                            if NotionSettings.shared.isConnected {
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
                        Text(
                            "Transcription and summaries run entirely on-device using Apple Intelligence. No audio or text data is sent to any server for AI processing."
                        )
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

@MainActor
@Observable
final class NotionSettings {
    static let shared = NotionSettings()

    private let tokenKey = "notion-token"
    private let databaseIdKey = "notion-database-id"
    private let databaseNameKey = "notion-database-name"
    private let workspaceNameKey = "notion-workspace-name"
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

    var databaseName: String {
        didSet {
            UserDefaults.standard.set(databaseName, forKey: databaseNameKey)
        }
    }

    var workspaceName: String {
        didSet {
            UserDefaults.standard.set(workspaceName, forKey: workspaceNameKey)
        }
    }

    var autoSync: Bool {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: autoSyncKey)
        }
    }

    /// Returns true if OAuth token is present
    var isConnected: Bool {
        !integrationToken.isEmpty
    }

    /// Returns true if connected AND database is selected
    var isConfigured: Bool {
        !integrationToken.isEmpty && !databaseId.isEmpty
    }

    private init() {
        self.integrationToken = (try? KeychainHelper.loadString(forKey: tokenKey)) ?? ""
        self.databaseId = UserDefaults.standard.string(forKey: databaseIdKey) ?? ""
        self.databaseName = UserDefaults.standard.string(forKey: databaseNameKey) ?? ""
        self.workspaceName = UserDefaults.standard.string(forKey: workspaceNameKey) ?? ""
        self.autoSync = UserDefaults.standard.bool(forKey: autoSyncKey)
    }

    func saveOAuthResult(_ result: OAuthResult) {
        integrationToken = result.accessToken
        workspaceName = result.workspaceName ?? ""
    }

    func selectDatabase(_ database: NotionDatabase) {
        databaseId = database.id
        databaseName = database.title
    }

    func disconnect() {
        try? KeychainHelper.delete(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: databaseIdKey)
        UserDefaults.standard.removeObject(forKey: databaseNameKey)
        UserDefaults.standard.removeObject(forKey: workspaceNameKey)
        integrationToken = ""
        databaseId = ""
        databaseName = ""
        workspaceName = ""
    }
}

// MARK: - Notion Settings View

struct NotionSettingsView: View {
    @Bindable private var notionSettings = NotionSettings.shared
    @StateObject private var oauthService = NotionOAuthService.shared
    @State private var databases: [NotionDatabase] = []
    @State private var isLoadingDatabases = false
    @State private var showDatabasePicker = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // Connection status section
            Section {
                if notionSettings.isConnected {
                    // Connected state
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Connected")
                                .font(.headline)
                            if !notionSettings.workspaceName.isEmpty {
                                Text(notionSettings.workspaceName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button("Disconnect from Notion", role: .destructive) {
                        notionSettings.disconnect()
                        databases = []
                    }
                } else {
                    // Not connected state
                    ConnectToNotionButton { result in
                        notionSettings.saveOAuthResult(result)
                        await loadDatabases()
                        if !databases.isEmpty {
                            showDatabasePicker = true
                        }
                    } onError: { error in
                        if case OAuthError.userCancelled = error {
                            // User cancelled, don't show error
                        } else {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } header: {
                Text("Notion Account")
            } footer: {
                if !notionSettings.isConnected {
                    Text("Sign in to sync your meeting notes to Notion.")
                }
            }

            // Database selection section
            if notionSettings.isConnected {
                Section {
                    if notionSettings.databaseId.isEmpty {
                        Button {
                            Task {
                                await loadDatabases()
                                showDatabasePicker = true
                            }
                        } label: {
                            HStack {
                                Label("Select Database", systemImage: "folder")
                                Spacer()
                                if isLoadingDatabases {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isLoadingDatabases)
                    } else {
                        HStack {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(notionSettings.databaseName.isEmpty ? "Database" : notionSettings.databaseName)
                                        .font(.body)
                                    Text(notionSettings.databaseId.prefix(8) + "...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                            }

                            Spacer()

                            Button("Change") {
                                Task {
                                    await loadDatabases()
                                    showDatabasePicker = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Sync Destination")
                } footer: {
                    Text("Meeting notes will be synced to this database. Make sure to share the database with the integration when prompted.")
                }
            }

            // Auto-sync toggle
            if notionSettings.isConfigured {
                Section {
                    Toggle("Auto-sync after recording", isOn: $notionSettings.autoSync)
                } header: {
                    Text("Sync Behavior")
                } footer: {
                    Text(
                        "When enabled, notes will automatically sync to Notion after transcription and summarization complete."
                    )
                }

                // Test connection
                Section {
                    TestConnectionButton()
                } header: {
                    Text("Diagnostics")
                }
            }
        }
        .navigationTitle("Notion")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showDatabasePicker) {
            DatabasePickerSheet(
                databases: databases,
                isLoading: isLoadingDatabases,
                onSelect: { database in
                    notionSettings.selectDatabase(database)
                    showDatabasePicker = false
                },
                onRefresh: {
                    await loadDatabases()
                }
            )
        }
        .onAppear {
            // If connected but no databases loaded, load them
            if notionSettings.isConnected && databases.isEmpty {
                Task {
                    await loadDatabases()
                }
            }
        }
    }

    private func loadDatabases() async {
        guard notionSettings.isConnected else { return }

        isLoadingDatabases = true
        errorMessage = nil

        do {
            databases = try await NotionOAuthService.shared.fetchAvailableDatabases(
                token: notionSettings.integrationToken
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingDatabases = false
    }
}

// MARK: - Connect to Notion Button

struct ConnectToNotionButton: View {
    let onSuccess: (OAuthResult) async -> Void
    let onError: (Error) -> Void

    @State private var isAuthenticating = false

    var body: some View {
        Button {
            authenticate()
        } label: {
            HStack {
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting...")
                } else {
                    Image(systemName: "link.badge.plus")
                    Text("Connect to Notion")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.black)
        .disabled(isAuthenticating)
    }

    private func authenticate() {
        isAuthenticating = true

        Task {
            do {
                #if os(iOS)
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                        let window = windowScene.windows.first
                    else {
                        throw OAuthError.sessionStartFailed
                    }
                    let result = try await NotionOAuthService.shared.startOAuthFlow(from: window)
                #else
                    guard let window = NSApplication.shared.windows.first else {
                        throw OAuthError.sessionStartFailed
                    }
                    let result = try await NotionOAuthService.shared.startOAuthFlow(from: window)
                #endif

                await onSuccess(result)
            } catch {
                onError(error)
            }

            await MainActor.run {
                isAuthenticating = false
            }
        }
    }
}

// MARK: - Database Picker Sheet

struct DatabasePickerSheet: View {
    let databases: [NotionDatabase]
    let isLoading: Bool
    let onSelect: (NotionDatabase) -> Void
    let onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && databases.isEmpty {
                    ProgressView("Loading databases...")
                } else if databases.isEmpty {
                    ContentUnavailableView {
                        Label("No Databases Found", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(
                            "No databases were shared with Swift Scribe. When connecting, make sure to select at least one database to share."
                        )
                    } actions: {
                        Button("Refresh") {
                            Task {
                                await onRefresh()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    List(databases) { database in
                        Button {
                            onSelect(database)
                        } label: {
                            HStack {
                                if let icon = database.icon {
                                    Text(icon)
                                        .font(.title2)
                                } else {
                                    Image(systemName: "folder")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading) {
                                    Text(database.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(database.id.prefix(12) + "...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Database")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !databases.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                await onRefresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Test Connection Button

struct TestConnectionButton: View {
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .disabled(isTesting)

            if let result = testResult {
                switch result {
                case .success:
                    Label("Connection successful", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
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
