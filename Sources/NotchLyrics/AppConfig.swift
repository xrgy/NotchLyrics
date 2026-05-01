import Foundation

public struct AppConfig: Decodable {
    public let spotifyClientID: String
    public let redirectPort: Int

    public init(spotifyClientID: String, redirectPort: Int = 43821) {
        self.spotifyClientID = spotifyClientID
        self.redirectPort = redirectPort
    }

    public static func load() -> AppConfig {
        if let clientID = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"], !clientID.isEmpty {
            let port = ProcessInfo.processInfo.environment["SPOTIFY_REDIRECT_PORT"].flatMap(Int.init) ?? 43821
            return AppConfig(spotifyClientID: clientID, redirectPort: port)
        }

        let fm = FileManager.default
        let appSupport = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchLyrics/config.json")
        if
            let data = try? Data(contentsOf: appSupport),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        {
            return config
        }

        return AppConfig(spotifyClientID: "")
    }

    public var isConfigured: Bool {
        !spotifyClientID.isEmpty
    }
}
