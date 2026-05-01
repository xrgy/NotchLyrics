import Combine
import Foundation

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var track: Track?
    @Published public private(set) var lyrics: LyricsPayload?
    @Published public private(set) var activeLineIndex: Int?
    @Published public private(set) var statusText = "未连接 Spotify"
    @Published public private(set) var errorText: String?

    private let authManager: SpotifyAuthManager
    private let spotifyClient: SpotifyClient
    private let spotifyLocalClient: SpotifyLocalClient
    private let lyricsProvider: LyricsProviding
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var currentProgressMS = 0
    private var lastTrackID: String?

    public init(config: AppConfig) {
        let auth = SpotifyAuthManager(config: config)
        self.authManager = auth
        self.spotifyClient = SpotifyClient(authManager: auth)
        self.spotifyLocalClient = SpotifyLocalClient()
        self.lyricsProvider = LRCLibClient()
        if config.isConfigured {
            self.statusText = auth.isAuthenticated ? "已连接 Spotify" : "等待 Spotify 登录或本地 Spotify"
        } else {
            self.statusText = "请先配置 SPOTIFY_CLIENT_ID，或直接打开本地 Spotify"
        }
    }

    public var canAuthorize: Bool {
        !authManager.isAuthenticated
    }

    public func authorize() {
        stop()
        Task {
            do {
                errorText = nil
                statusText = "正在打开 Spotify 登录"
                try await authManager.authorize()
                statusText = "已连接 Spotify"
                start()
            } catch {
                errorText = userVisibleMessage(for: error, fallback: "Spotify 登录失败")
                statusText = "Spotify 登录失败"
            }
        }
    }

    public func signOut() {
        authManager.signOut()
        track = nil
        lyrics = nil
        activeLineIndex = nil
        currentProgressMS = 0
        lastTrackID = nil
        statusText = "等待 Spotify 登录或本地 Spotify"
        stop()
        start()
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await refreshPlayback()
                try? await Task.sleep(for: .seconds(3))
            }
        }

        tickTask = Task {
            while !Task.isCancelled {
                updateProgressLocally()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        tickTask?.cancel()
        pollTask = nil
        tickTask = nil
    }

    public func previousTrack() {
        performLocalPlaybackCommand(.previousTrack)
    }

    public func togglePlayback() {
        performLocalPlaybackCommand(.togglePlayPause)
    }

    public func nextTrack() {
        performLocalPlaybackCommand(.nextTrack)
    }

    private func performLocalPlaybackCommand(_ command: SpotifyLocalClient.PlaybackCommand) {
        Task { @MainActor in
            do {
                errorText = nil
                try await spotifyLocalClient.perform(command)
                await refreshPlayback()
            } catch {
                errorText = userVisibleMessage(for: error, fallback: "Spotify 控制失败")
                statusText = "Spotify 控制失败"
            }
        }
    }

    private func refreshPlayback() async {
        do {
            let playback = try await resolvePlayback()

            guard let current = playback.track else {
                track = nil
                lyrics = nil
                activeLineIndex = nil
                lastTrackID = nil
                errorText = nil
                statusText = playback.statusText
                return
            }

            track = current
            currentProgressMS = current.progressMS
            statusText = playback.statusText
            updateActiveLine()

            if lastTrackID != current.id {
                lastTrackID = current.id
                errorText = nil
                do {
                    lyrics = try await lyricsProvider.fetchLyrics(for: current)
                } catch {
                    lyrics = nil
                    errorText = nil
                }
                updateActiveLine()
            }
        } catch {
            track = nil
            lyrics = nil
            activeLineIndex = nil
            errorText = userVisibleMessage(for: error, fallback: "读取 Spotify 播放状态失败")
            statusText = "读取 Spotify 播放状态失败"
        }
    }

    private func resolvePlayback() async throws -> PlaybackResolution {
        do {
            if let current = try await spotifyClient.currentTrack() {
                return PlaybackResolution(
                    track: current,
                    statusText: current.isPlaying ? "正在播放" : "已暂停"
                )
            }
        } catch {
            if shouldFallbackToLocal(for: error) {
                return try await resolveLocalPlayback()
            }
            throw error
        }

        return try await resolveLocalPlayback()
    }

    private func resolveLocalPlayback() async throws -> PlaybackResolution {
        let local = try await spotifyLocalClient.currentTrack()
        if let track = local.track {
            return PlaybackResolution(
                track: track,
                statusText: track.isPlaying ? "正在播放 · 本地 Spotify" : "已暂停 · 本地 Spotify"
            )
        }

        return PlaybackResolution(track: nil, statusText: local.sourceDescription)
    }

    private func shouldFallbackToLocal(for error: Error) -> Bool {
        if error is SpotifyAuthError {
            return true
        }

        if case let SpotifyClientError.httpError(status, _) = error, status == 403 {
            return true
        }

        return false
    }

    private func updateProgressLocally() {
        guard let track else { return }
        if track.isPlaying {
            currentProgressMS = min(currentProgressMS + 250, track.durationMS)
        }
        updateActiveLine()
    }

    private func updateActiveLine() {
        guard let lyrics else {
            activeLineIndex = nil
            return
        }

        let idx = lyrics.lines.lastIndex(where: { $0.timestampMS <= currentProgressMS })
        activeLineIndex = idx
    }

    private func userVisibleMessage(for error: Error, fallback: String) -> String {
        if let authError = error as? SpotifyAuthError {
            return authError.localizedDescription
        }

        if let spotifyError = error as? SpotifyClientError {
            return spotifyError.localizedDescription
        }

        if let lyricsError = error as? LyricsError {
            return lyricsError.localizedDescription
        }

        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "The operation couldn’t be completed." || text == "The operation could not be completed." {
            return fallback
        }

        return fallback
    }
}

private struct PlaybackResolution {
    let track: Track?
    let statusText: String
}
