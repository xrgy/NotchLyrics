import AppKit
import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var model: AppModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack {
                appIcon
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NotchLyrics")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)

                    Text(version)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(playbackLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.errorText == nil ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 8) {
                    if model.canAuthorize {
                        Button("连接 Spotify") {
                            model.authorize()
                        }
                    } else {
                        Button("断开连接") {
                            model.signOut()
                        }
                    }
                    Button("退出") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private var appIcon: some View {
        Group {
            if let image = AppIcon.image() {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var playbackLine: String {
        if let track = model.track {
            return [track.title, track.artistLine]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }

        if let error = model.errorText {
            return error
        }

        return model.statusText
    }
}
