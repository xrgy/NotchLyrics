import SwiftUI

enum NotchOverlayMetrics {
    static let width: CGFloat = 286
    static let height: CGFloat = 62
    static let notchWidth: CGFloat = 170
    static let notchDepth: CGFloat = 20
    static let textTopPadding: CGFloat = 40
    static let sideSlotWidth: CGFloat = 44
    static let artworkSize: CGFloat = 34
    static let artworkCornerRadius: CGFloat = 9
    static let expandedHeight: CGFloat = 168
    static let expandedArtworkSize: CGFloat = 86
    static let expandedArtworkCornerRadius: CGFloat = 16
}

@MainActor
final class NotchOverlayState: ObservableObject {
    @Published var expansionProgress: CGFloat = 0
    @Published var showsExpandedContent = false
    @Published var expandedWidth: CGFloat
    @Published var containerWidth = NotchOverlayMetrics.width
    @Published var containerHeight = NotchOverlayMetrics.height

    let expandedHeight: CGFloat

    init(expandedWidth: CGFloat, expandedHeight: CGFloat = NotchOverlayMetrics.expandedHeight) {
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
    }

    var currentWidth: CGFloat {
        interpolate(from: NotchOverlayMetrics.width, to: expandedWidth).rounded()
    }

    var currentHeight: CGFloat {
        interpolate(from: NotchOverlayMetrics.height, to: expandedHeight).rounded()
    }

    var collapsedOpacity: Double {
        Double(1 - fadeProgress)
    }

    var expandedOpacity: Double {
        Double(fadeProgress)
    }

    var collapsedYOffset: CGFloat {
        -6 * fadeProgress
    }

    var collapsedSideOpacity: Double {
        let normalized = expansionProgress / 0.12
        let clamped = min(1, max(0, normalized))
        let eased = clamped * clamped * (3 - 2 * clamped)
        return Double(1 - eased)
    }

    var expandedYOffset: CGFloat {
        8 * (1 - fadeProgress)
    }

    func setContainerExpanded(_ expanded: Bool) {
        containerWidth = expanded ? expandedWidth : NotchOverlayMetrics.width
        containerHeight = expanded ? expandedHeight : NotchOverlayMetrics.height
    }

    private var fadeProgress: CGFloat {
        let start: CGFloat = 0.12
        let end: CGFloat = 0.78
        let normalized = (expansionProgress - start) / (end - start)
        let clamped = min(1, max(0, normalized))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * expansionProgress
    }
}

struct NotchOverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var overlayState: NotchOverlayState
    private let onHoverChange: @MainActor (Bool) -> Void

    init(
        model: AppModel,
        overlayState: NotchOverlayState,
        onHoverChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.overlayState = overlayState
        self.onHoverChange = onHoverChange
    }

    var body: some View {
        animatedSurface
            .frame(width: overlayState.containerWidth, height: overlayState.containerHeight, alignment: .top)
            .background(Color.clear)
            .clipShape(NotchWrapShape(notchWidth: NotchOverlayMetrics.notchWidth, notchDepth: NotchOverlayMetrics.notchDepth))
    }

    private var animatedSurface: some View {
        ZStack(alignment: .top) {
            NotchWrapShape(notchWidth: NotchOverlayMetrics.notchWidth, notchDepth: NotchOverlayMetrics.notchDepth)
                .fill(backgroundGradient)
            NotchWrapShape(notchWidth: NotchOverlayMetrics.notchWidth, notchDepth: NotchOverlayMetrics.notchDepth)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            collapsedContent
                .opacity(overlayState.collapsedOpacity)
                .offset(y: overlayState.collapsedYOffset)
                .allowsHitTesting(!overlayState.showsExpandedContent)

            if overlayState.showsExpandedContent || overlayState.expandedOpacity > 0 {
                expandedContent
                    .opacity(overlayState.expandedOpacity)
                    .offset(y: overlayState.expandedYOffset)
                    .allowsHitTesting(overlayState.showsExpandedContent)
            }
        }
        .frame(width: overlayState.currentWidth, height: overlayState.currentHeight)
        .contentShape(Rectangle())
        .clipShape(NotchWrapShape(notchWidth: NotchOverlayMetrics.notchWidth, notchDepth: NotchOverlayMetrics.notchDepth))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .compositingGroup()
        .onHover(perform: onHoverChange)
    }

    private var collapsedContent: some View {
        ZStack(alignment: .top) {
            sideContent
                .frame(width: NotchOverlayMetrics.width, height: NotchOverlayMetrics.height, alignment: .center)
                .opacity(overlayState.collapsedSideOpacity)

            centerTextBlock
                .padding(.top, NotchOverlayMetrics.textTopPadding)
                .padding(.horizontal, 58)
        }
        .frame(width: NotchOverlayMetrics.width, height: NotchOverlayMetrics.height)
    }

    private var expandedContent: some View {
        HStack(spacing: 18) {
            expandedArtworkSection
                .frame(width: 112)

            expandedControlsSection
                .frame(width: 138)

            expandedLyricsSection
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, NotchOverlayMetrics.notchDepth + 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(width: overlayState.expandedWidth, height: overlayState.expandedHeight, alignment: .top)
        .clipped()
    }

    private var expandedArtworkSection: some View {
        VStack(spacing: 8) {
            albumArtwork(
                size: NotchOverlayMetrics.expandedArtworkSize,
                cornerRadius: NotchOverlayMetrics.expandedArtworkCornerRadius,
                placeholderFontSize: 22
            )

            Text(model.track?.album ?? "No Album")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var expandedControlsSection: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                controlButton(systemName: "backward.fill", diameter: 34) {
                    model.previousTrack()
                }

                controlButton(systemName: model.track?.isPlaying == true ? "pause.fill" : "play.fill", diameter: 44) {
                    model.togglePlayback()
                }

                controlButton(systemName: "forward.fill", diameter: 34) {
                    model.nextTrack()
                }
            }
            .disabled(model.track == nil)

            Text(model.track?.isPlaying == true ? "正在播放" : "已暂停")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))
        }
    }

    private var expandedLyricsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(primaryText)
                .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryColor)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            if let lowerText, !lowerText.isEmpty {
                Text(lowerText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if let track = model.track {
                Text("\(track.title) · \(track.artistLine)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var sideContent: some View {
        HStack(spacing: 0) {
            artwork
                .frame(width: NotchOverlayMetrics.sideSlotWidth, alignment: .leading)

            Spacer(minLength: NotchOverlayMetrics.notchWidth)

            MusicPulseIcon(isPlaying: model.track?.isPlaying == true)
                .frame(width: NotchOverlayMetrics.sideSlotWidth, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }

    private var centerTextBlock: some View {
        Text(primaryText)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(primaryColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
    }

    private var artwork: some View {
        albumArtwork(
            size: NotchOverlayMetrics.artworkSize,
            cornerRadius: NotchOverlayMetrics.artworkCornerRadius,
            placeholderFontSize: 10
        )
    }

    private func albumArtwork(size: CGFloat, cornerRadius: CGFloat, placeholderFontSize: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))

            if let artworkURL = model.track?.artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderArtwork(fontSize: placeholderFontSize)
                }
            } else {
                placeholderArtwork(fontSize: placeholderFontSize)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func placeholderArtwork(fontSize: CGFloat) -> some View {
        Image(systemName: "music.note")
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.68))
    }

    private func controlButton(systemName: String, diameter: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.36, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(OverlayControlButtonStyle(diameter: diameter))
    }

    private var primaryText: String {
        if let text = currentLyricText {
            return text
        }
        if let error = model.errorText {
            return error
        }
        return model.track?.title ?? "等待播放"
    }

    private var lowerText: String? {
        if let lyrics = model.lyrics, !lyrics.lines.isEmpty {
            return nextDistinctLine(in: lyrics)
        }
        if let track = model.track, !track.artistLine.isEmpty {
            return track.artistLine
        }
        return nil
    }

    private var primaryColor: Color {
        model.errorText == nil ? .white : Color(red: 1.0, green: 0.66, blue: 0.36)
    }

    private var currentLyricText: String? {
        guard let lyrics = model.lyrics, !lyrics.lines.isEmpty else { return nil }
        if let current = currentLine(in: lyrics) {
            return displayableText(current.text) ?? "…"
        }
        return displayableText(lyrics.lines.first?.text) ?? "…"
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.105, green: 0.105, blue: 0.12),
                Color.black.opacity(0.985)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func currentLine(in lyrics: LyricsPayload) -> LyricsLine? {
        guard let index = model.activeLineIndex, lyrics.lines.indices.contains(index) else { return nil }
        return lyrics.lines[index]
    }

    private func nextDistinctLine(in lyrics: LyricsPayload) -> String? {
        guard
            let index = model.activeLineIndex,
            let currentText = currentLyricText
        else {
            return nil
        }

        let current = normalizedLyricText(currentText)
        return lyrics.lines
            .dropFirst(index + 1)
            .compactMap { displayableText($0.text) }
            .first { normalizedLyricText($0) != current }
    }

    private func displayableText(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func normalizedLyricText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

private struct OverlayControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(Color.white.opacity(isEnabled ? 0.14 : 0.06))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.05), lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.42)
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MusicPulseIcon: View {
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            pulseBar(height: 7, delay: 0.0)
            pulseBar(height: 11, delay: 0.12)
            pulseBar(height: 8, delay: 0.24)
        }
        .frame(width: 18, height: 14, alignment: .center)
    }

    private func pulseBar(height: CGFloat, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(isPlaying ? 0.82 : 0.42))
            .frame(width: 3, height: height)
            .scaleEffect(y: isPlaying ? 1.0 : 0.55, anchor: .center)
            .animation(
                isPlaying
                    ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(delay)
                    : .easeOut(duration: 0.2),
                value: isPlaying
            )
    }
}

private struct NotchWrapShape: Shape {
    let notchWidth: CGFloat
    let notchDepth: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 26
        let notchRadius: CGFloat = 16
        let notchLeft = rect.midX - notchWidth / 2
        let notchRight = rect.midX + notchWidth / 2

        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: notchLeft - notchRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: notchLeft, y: notchRadius), control: CGPoint(x: notchLeft, y: 0))
        path.addLine(to: CGPoint(x: notchLeft, y: notchDepth - notchRadius))
        path.addQuadCurve(to: CGPoint(x: notchLeft + notchRadius, y: notchDepth), control: CGPoint(x: notchLeft, y: notchDepth))
        path.addLine(to: CGPoint(x: notchRight - notchRadius, y: notchDepth))
        path.addQuadCurve(to: CGPoint(x: notchRight, y: notchDepth - notchRadius), control: CGPoint(x: notchRight, y: notchDepth))
        path.addLine(to: CGPoint(x: notchRight, y: notchRadius))
        path.addQuadCurve(to: CGPoint(x: notchRight + notchRadius, y: 0), control: CGPoint(x: notchRight, y: 0))
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: radius), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
    }
}
