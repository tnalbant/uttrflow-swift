// Home's hero card: the headline, the three features, the waveform, the start pill and the mood picture.

import UttrflowUX
import AppKit
import SwiftUI

/// The card across the top of home, with the picture for the time of day fading in from its right.
struct HomeHeroCard: View {
    let hero: HomeHero
    let mood: HomeMood
    var onIntent: (MainIntent) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The hero's fixed height and the width its words and waveform take.
    static let height: CGFloat = 282
    static let contentWidth: CGFloat = 470

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headline
            features
                .padding(.top, 12)
                .padding(.bottom, 20)
            HomeWaveform()
                .frame(height: 56)
            startButton
                .padding(.top, 22)
        }
        .frame(maxWidth: Self.contentWidth, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.height)
        .background(alignment: .trailing) { HomeMoodPicture(mood: mood) }
        .background { ground }
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(PagePalette.dictation.opacity(0.28), lineWidth: 1)
        }
        .shadow(
            color: PagePalette.dictation.opacity(isDark ? 0.18 : 0.22), radius: isDark ? 20 : 14,
            y: isDark ? 0 : 8)
    }

    private var isDark: Bool { colorScheme == .dark }

    /// "Your voice, finished for you.", the second half in the three accents.
    private var headline: some View {
        let accents = LinearGradient(
            colors: [PagePalette.dictation, PagePalette.suggestion, PagePalette.clipboard],
            startPoint: .leading, endPoint: .trailing)
        return Text("\(hero.lead) \(Text(hero.emphasis).foregroundStyle(accents))")
            .font(BrandFont.display(size: 40, weight: .heavy))
            .tracking(-1.6)
            .foregroundStyle(PagePalette.text)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// The three features, each in its own accent, separated by dots.
    private var features: some View {
        HStack(spacing: 4) {
            ForEach(Array(hero.features.enumerated()), id: \.element) { index, feature in
                if index > 0 {
                    Text("·").foregroundStyle(PagePalette.soft)
                }
                Text(feature.title).foregroundStyle(Self.accent(for: feature))
            }
        }
        .font(BrandFont.display(size: 16, weight: .regular))
        .accessibilityElement(children: .combine)
    }

    /// Each feature's accent: teal for dictation, lilac for suggestions, amber for the clipboard.
    static func accent(for feature: HomeFeature) -> Color {
        switch feature {
        case .dictation: PagePalette.dictation
        case .suggestions: PagePalette.suggestion
        case .clipboard: PagePalette.clipboard
        }
    }

    /// The pill, drawn plain under a clear button and dimmed per colour rather than as a layer, so nothing clips its glow.
    private var startButton: some View {
        let dim = hero.canStart ? 1.0 : 0.45
        return HStack(spacing: 12) {
            Image(systemName: hero.start.symbolName ?? "mic")
                .font(.system(size: 16, weight: .medium))
            Text(hero.start.title)
                .font(.system(size: 15, weight: .medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 6)
        }
        .foregroundStyle(PagePalette.text.opacity(dim))
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .background(PagePalette.dictation.opacity(0.08 * dim), in: Capsule(style: .circular))
        .overlay {
            PillGlow(
                inner: PagePalette.suggestion, outer: PagePalette.dictation,
                strength: isDark ? dim : dim * 0.55)
        }
        .overlay {
            Capsule(style: .circular).strokeBorder(PagePalette.dictation.opacity(dim), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
        .overlay {
            Button {
                onIntent(hero.start.intent)
            } label: {
                Capsule(style: .circular).fill(.clear).contentShape(Capsule(style: .circular))
            }
            .buttonStyle(.plain)
            .disabled(!hero.canStart)
            .accessibilityLabel(hero.start.title)
        }
        .help(hero.canStart ? "Start or stop a dictation" : "Uttrflow cannot listen yet")
    }

    /// The card's ground with a blue glow behind the picture and a violet one rising at the lower left.
    private var ground: some View {
        PagePalette.hero
            .overlay {
                EllipticalGradient(
                    colors: [PagePalette.glowBlue.opacity(isDark ? 0.28 : 0.14), .clear],
                    center: UnitPoint(x: 0.8, y: 0.5), startRadiusFraction: 0, endRadiusFraction: 0.6)
            }
            .overlay {
                EllipticalGradient(
                    colors: [PagePalette.glowViolet.opacity(isDark ? 0.2 : 0.12), .clear],
                    center: UnitPoint(x: 0.1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.55)
            }
            .accessibilityHidden(true)
    }
}

/// The start pill's glow as fading circular rings, drawn without blur or shadow so it never shows a hard edge.
struct PillGlow: View {
    let inner: Color
    let outer: Color
    /// How strong the glow is, from 0 to 1.
    let strength: Double

    var body: some View {
        ZStack {
            // Lilac softening inward from the rim.
            ForEach(1..<5) { step in
                Capsule(style: .circular)
                    .inset(by: CGFloat(step) * 2)
                    .stroke(inner.opacity(0.16 * strength / Double(step)), lineWidth: 2)
            }
            // Teal fading outward past the rim, eased so no ring stands out.
            ForEach(1..<11) { step in
                Capsule(style: .circular)
                    .stroke(outer.opacity(0.2 * strength * pow(1 - Double(step) / 11, 2)), lineWidth: 1.5)
                    .padding(-CGFloat(step) * 1.2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A still waveform of mono bars, tallest in the middle and fading at both ends.
struct HomeWaveform: View {
    /// How many bars are drawn.
    static let count = 64

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 3
            let width = max(1, (size.width - gap * CGFloat(Self.count - 1)) / CGFloat(Self.count))
            for index in 0..<Self.count {
                let (height, opacity) = Self.bar(index)
                let barHeight = size.height * height
                let rect = CGRect(
                    x: CGFloat(index) * (width + gap), y: (size.height - barHeight) / 2,
                    width: width, height: barHeight)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(2, width / 2)),
                    with: .color(PagePalette.waveform.opacity(opacity)))
            }
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88), .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityHidden(true)
    }

    /// One bar's height as a share of the row and its opacity: a bell across the row, rippled.
    static func bar(_ index: Int) -> (height: Double, opacity: Double) {
        let position = Double(index) / Double(count - 1)
        let bell = exp(-pow(position - 0.5, 2) * 9)
        let ripple = 0.45 + 0.55 * abs(sin(Double(index) * 1.7))
        return ((10 + 90 * bell * ripple) / 100, 0.35 + 0.6 * bell)
    }
}

/// The picture for the part of the day, filling the card's right side and fading into it.
struct HomeMoodPicture: View {
    let mood: HomeMood

    /// The widest the picture is drawn, and the narrowest before it is left out.
    static let widest: CGFloat = 390
    static let narrowest: CGFloat = 150

    var body: some View {
        GeometryReader { proxy in
            let width = min(Self.widest, proxy.size.width - HomeHeroCard.contentWidth - 30)
            if width >= Self.narrowest, let image = MoodPictures.image(for: mood) {
                picture(image, width: width, height: proxy.size.height)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    /// The picture cropped to fill, a little above centre, masked to fade in from the left.
    private func picture(_ image: NSImage, width: CGFloat, height: CGFloat) -> some View {
        let scaled = image.size.width > 0 ? width * image.size.height / image.size.width : height
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            // Framed at 40% down rather than 50%, where the faces sit.
            .offset(y: max(0, scaled - height) * 0.1)
            .frame(width: width, height: height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.42)],
                    startPoint: .leading, endPoint: .trailing)
            }
    }
}

/// The six mood pictures, read from the bundle once each.
@MainActor
enum MoodPictures {
    private static var loaded: [HomeMood: NSImage] = [:]

    /// The picture for a mood, or `nil` when the bundle lacks it.
    static func image(for mood: HomeMood) -> NSImage? {
        if let image = loaded[mood] { return image }
        let image = Bundle.module.image(forResource: mood.imageName)
        loaded[mood] = image
        return image
    }
}
