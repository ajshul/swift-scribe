import AuthenticationServices
import Combine
import Foundation

/// Handles Notion OAuth 2.0 authentication flow
@MainActor
final class NotionOAuthService: NSObject, ObservableObject {
    static let shared = NotionOAuthService()

    // MARK: - OAuth Configuration
    // TODO: Replace with your Notion OAuth app credentials from notion.so/my-integrations
    // Create a "Public integration" to get these values
    private let clientId = "YOUR_CLIENT_ID"
    private let clientSecret = "YOUR_CLIENT_SECRET"
    private let redirectUri = "swiftscribe://notion-callback"

    private let authorizeURL = "https://api.notion.com/v1/oauth/authorize"
    private let tokenURL = "https://api.notion.com/v1/oauth/token"

    @Published var isAuthenticating = false
    @Published var authError: String?

    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    private override init() {
        super.init()
    }

    // MARK: - OAuth Flow

    /// Start the OAuth authorization flow
    func startOAuthFlow(from anchor: ASPresentationAnchor) async throws -> OAuthResult {
        isAuthenticating = true
        authError = nil
        presentationAnchor = anchor

        defer {
            isAuthenticating = false
            presentationAnchor = nil
        }

        // Build authorization URL
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user")
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        // Start web authentication session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "swiftscribe"
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authenticationFailed(error.localizedDescription))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.noCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session

            if !session.start() {
                continuation.resume(throwing: OAuthError.sessionStartFailed)
            }
        }

        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.noAuthorizationCode
        }

        // Exchange code for access token
        let tokenResponse = try await exchangeCodeForToken(code: code)

        return tokenResponse
    }

    /// Exchange authorization code for access token
    private func exchangeCodeForToken(code: String) async throws -> OAuthResult {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Basic auth with client credentials
        let credentials = "\(clientId):\(clientSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error_description"] as? String ?? errorJson["error"] as? String {
                throw OAuthError.tokenExchangeFailed(errorMessage)
            }
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.invalidResponse
        }

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.noAccessToken
        }

        // Extract workspace info
        let workspaceInfo = json["workspace_name"] as? String
        let workspaceId = json["workspace_id"] as? String
        let botId = json["bot_id"] as? String

        return OAuthResult(
            accessToken: accessToken,
            workspaceName: workspaceInfo,
            workspaceId: workspaceId,
            botId: botId
        )
    }

    // MARK: - Database Discovery

    /// Search for databases the user has shared with the integration
    func fetchAvailableDatabases(token: String) async throws -> [NotionDatabase] {
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/search")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "filter": ["property": "object", "value": "database"],
            "sort": ["direction": "descending", "timestamp": "last_edited_time"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.databaseSearchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw OAuthError.invalidResponse
        }

        return results.compactMap { db -> NotionDatabase? in
            guard let id = db["id"] as? String else { return nil }

            // Extract title from title property
            var title = "Untitled Database"
            if let titleArray = db["title"] as? [[String: Any]],
               let firstTitle = titleArray.first,
               let plainText = firstTitle["plain_text"] as? String {
                title = plainText
            }

            // Extract icon
            var icon: String?
            if let iconObj = db["icon"] as? [String: Any] {
                if iconObj["type"] as? String == "emoji" {
                    icon = iconObj["emoji"] as? String
                }
            }

            return NotionDatabase(id: id, title: title, icon: icon)
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension NotionOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor ?? ASPresentationAnchor()
    }
}

// MARK: - Models

struct OAuthResult: Sendable {
    let accessToken: String
    let workspaceName: String?
    let workspaceId: String?
    let botId: String?
}

struct NotionDatabase: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let icon: String?
}

enum OAuthError: LocalizedError {
    case invalidURL
    case userCancelled
    case authenticationFailed(String)
    case noCallbackURL
    case sessionStartFailed
    case noAuthorizationCode
    case invalidResponse
    case tokenExchangeFailed(String)
    case noAccessToken
    case databaseSearchFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid authorization URL"
        case .userCancelled:
            return "Sign in was cancelled"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .noCallbackURL:
            return "No callback URL received"
        case .sessionStartFailed:
            return "Failed to start authentication session"
        case .noAuthorizationCode:
            return "No authorization code in callback"
        case .invalidResponse:
            return "Invalid response from Notion"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .noAccessToken:
            return "No access token in response"
        case .databaseSearchFailed:
            return "Failed to search for databases"
        }
    }
}
