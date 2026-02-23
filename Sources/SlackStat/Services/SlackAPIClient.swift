import Foundation

enum SlackAPIError: Error, LocalizedError {
    case httpError(Int)
    case authError
    case rateLimited(retryAfter: TimeInterval)
    case apiError(String)
    case networkError(Error)
    case enterpriseRestricted

    var errorDescription: String? {
        switch self {
        case .httpError(let code): return "HTTP error \(code)"
        case .authError: return "Authentication failed"
        case .rateLimited(let after): return "Rate limited, retry after \(after)s"
        case .apiError(let msg): return "Slack API error: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .enterpriseRestricted: return "API restricted on enterprise workspace"
        }
    }
}

final class SlackAPIClient: Sendable {
    let token: String
    let cookie: String
    let baseURL: String
    private let session: URLSession

    /// Create a client. If `domain` is provided, API calls go to `https://<domain>.slack.com/api/`.
    /// Otherwise they go to `https://slack.com/api/`.
    init(token: String, cookie: String, domain: String? = nil, session: URLSession = .shared) {
        self.token = token
        self.cookie = cookie
        self.baseURL = domain.map { "https://\($0).slack.com/api/" } ?? "https://slack.com/api/"
        self.session = session
    }

    func buildRequest(method: String, params: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("d=\(cookie)", forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = params
        bodyParams["token"] = token
        let body = bodyParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        return request
    }

    // MARK: - API Methods

    func authTest(teamId: String? = nil) async throws -> AuthTestResponse {
        var params: [String: String] = [:]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "auth.test", params: params)
        return try await execute(request: request)
    }

    func fetchCounts(teamId: String? = nil) async throws -> ClientCountsResponse {
        var params: [String: String] = [:]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "client.counts", params: params)
        return try await execute(request: request)
    }

    func fetchConversationInfo(channelId: String, teamId: String? = nil) async throws -> ConversationInfoResponse {
        var params = ["channel": channelId]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "conversations.info", params: params)
        return try await execute(request: request)
    }

    func fetchUserInfo(userId: String, teamId: String? = nil) async throws -> UserInfoResponse {
        var params = ["user": userId]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "users.info", params: params)
        return try await execute(request: request)
    }

    func fetchUserPrefs(teamId: String? = nil) async throws -> UserPrefsResponse {
        var params: [String: String] = [:]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "users.prefs.get", params: params)
        return try await execute(request: request)
    }

    func fetchUserBoot(teamId: String? = nil) async throws -> UserBootSectionsResponse {
        var params: [String: String] = [:]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "client.userBoot", params: params)
        return try await execute(request: request)
    }

    /// Try the dedicated channel sections endpoint
    func fetchChannelSections(teamId: String? = nil) async throws -> UserBootSectionsResponse {
        var params: [String: String] = [:]
        if let teamId { params["team_id"] = teamId }
        let request = buildRequest(method: "users.channelSections.list", params: params)
        return try await execute(request: request)
    }

    // MARK: - Request Execution

    private func execute<T: Decodable>(request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SlackAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlackAPIError.httpError(0)
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) } ?? 30
            throw SlackAPIError.rateLimited(retryAfter: retryAfter)
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw SlackAPIError.authError
            }
            throw SlackAPIError.httpError(httpResponse.statusCode)
        }

        // Check for Slack-level errors
        if let errorCheck = try? JSONDecoder().decode(SlackErrorResponse.self, from: data),
            !errorCheck.ok
        {
            let errorMsg = errorCheck.error ?? "unknown"
            if errorMsg == "not_authed" || errorMsg == "invalid_auth"
                || errorMsg == "token_revoked"
            {
                throw SlackAPIError.authError
            }
            if errorMsg == "enterprise_is_restricted" {
                throw SlackAPIError.enterpriseRestricted
            }
            throw SlackAPIError.apiError(errorMsg)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
