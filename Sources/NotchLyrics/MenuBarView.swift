import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var model: AppModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NotchLyrics \(version)")
                .font(.system(size: 16, weight: .bold))

            Text(model.track.map { "\($0.title) · \($0.artistLine)" } ?? model.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let error = model.errorText {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            HStack {
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
        .padding(14)
        .frame(width: 320)
    }
}
