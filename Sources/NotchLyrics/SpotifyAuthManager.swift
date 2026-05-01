import AppKit
import CryptoKit
import Foundation
import Network

enum SpotifyAuthError: LocalizedError {
    case missingClientID
    case callbackFailed
    case tokenExchangeFailed
    case tokenExchangeRejected(status: Int, details: String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "缺少 Spotify Client ID。请配置 SPOTIFY_CLIENT_ID。"
        case .callbackFailed:
            return "Spotify 回调失败。"
        case .tokenExchangeFailed:
            return "Spotify 令牌交换失败。"
        case let .tokenExchangeRejected(status, details):
            return "Spotify 令牌交换失败 (\(status)): \(details)"
        }
    }
}

struct SpotifyToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

@MainActor
final class SpotifyAuthManager: ObservableObject {
    @Published private(set) var token: SpotifyToken?

    private let session: URLSession
    private let config: AppConfig
    private let tokenStore: TokenStore
    private var codeVerifier = ""

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.tokenStore = TokenStore()
        self.token = self.tokenStore.load()
    }

    var isAuthenticated: Bool {
        token != nil
    }

    func validAccessToken() async throws -> String {
        if let token, !token.isExpired {
            return token.accessToken
        }

        if let refreshed = try await refreshTokenIfNeeded() {
            return refreshed.accessToken
        }

        throw SpotifyAuthError.tokenExchangeFailed
    }

    func authorize() async throws {
        guard config.isConfigured else {
            throw SpotifyAuthError.missingClientID
        }

        let verifier = Self.randomVerifier()
        codeVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)
        let redirectURI = "http://127.0.0.1:\(config.redirectPort)/callback"

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.spotifyClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "user-read-currently-playing user-read-playback-state"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let url = components.url else {
            throw SpotifyAuthError.callbackFailed
        }

        let callback = try await LocalCallbackServer(port: UInt16(config.redirectPort)).waitForCode(open: url)
        try await exchangeCodeForToken(callback.code, redirectURI: redirectURI)
    }

    func signOut() {
        token = nil
        tokenStore.clear()
    }

    private func exchangeCodeForToken(_ code: String, redirectURI: String) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": config.spotifyClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        request.httpBody = body.percentEncoded()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAuthError.tokenExchangeFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyAuthError.tokenExchangeRejected(
                status: http.statusCode,
                details: Self.decodeErrorDetails(from: data)
            )
        }

        let dto = try JSONDecoder().decode(TokenResponse.self, from: data)
        let token = SpotifyToken(
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))
        )
        self.token = token
        tokenStore.save(token)
    }

    private func refreshTokenIfNeeded() async throws -> SpotifyToken? {
        guard let token, let refreshToken = token.refreshToken else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": config.spotifyClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ].percentEncoded()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        let dto = try JSONDecoder().decode(TokenResponse.self, from: data)
        let refreshed = SpotifyToken(
            accessToken: dto.accessToken,
            refreshToken: dto.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(dto.expiresIn))
        )
        self.token = refreshed
        tokenStore.save(refreshed)
        return refreshed
    }

    private static func randomVerifier() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func decodeErrorDetails(from data: Data) -> String {
        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? String
        {
            let description = json["error_description"] as? String
            return [error, description].compactMap { $0 }.joined(separator: " - ")
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "未知错误"
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct CallbackResult {
    let code: String
}

private final class LocalCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private let lock = NSLock()
    private var didFinish = false

    init(port: UInt16) {
        self.port = port
    }

    func waitForCode(open url: URL) async throws -> CallbackResult {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .global())
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        let requestString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        let code = Self.extractCode(from: requestString)
                        let response = Self.httpResponse(code != nil)
                        connection.send(content: response, completion: .contentProcessed { _ in
                            connection.cancel()
                            listener.cancel()
                            self.finish(continuation: continuation, code: code)
                        })
                    }
                }
                listener.start(queue: .global())
                NSWorkspace.shared.open(url)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func extractCode(from request: String) -> String? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://127.0.0.1\(path)") else { return nil }
        return components.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private static func httpResponse(_ ok: Bool) -> Data {
        let message = ok ? "Spotify connected. You can close this tab." : "Spotify authentication failed."
        let status = ok ? "200 OK" : "400 Bad Request"
        let body = "<html><body style=\"font-family: -apple-system; padding: 24px;\">\(message)</body></html>"
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return Data(response.utf8)
    }

    private func finish(
        continuation: CheckedContinuation<CallbackResult, Error>,
        code: String?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !didFinish else { return }
        didFinish = true

        if let code {
            continuation.resume(returning: CallbackResult(code: code))
        } else {
            continuation.resume(throwing: SpotifyAuthError.callbackFailed)
        }
    }
}

private final class TokenStore {
    private let url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/NotchLyrics/token.json")

    func load() -> SpotifyToken? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(token) {
            try? data.write(to: url)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        let body = map { key, value in
            let encodedKey = key
                .replacingOccurrences(of: " ", with: "+")
                .addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value
                .replacingOccurrences(of: " ", with: "+")
                .addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .sorted()
        .joined(separator: "&")
        return Data(body.utf8)
    }
}
