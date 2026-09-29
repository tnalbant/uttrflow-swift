// The first try's picture: the keyboard's bottom-left keys with the shortcut lit, and the field the words land in.

import SwiftUI
import UttrflowUX

/// The bottom-left keys of a Mac keyboard, the shortcut's lit teal under a bracket saying what to do.
struct OnboardingKeyboardCorner: View {
    let keyboard: OnboardingKeyboard
    /// Whether its window is the one being used; starts still so a window opened behind others never moves.
    @State private var attended = false

    /// Each key's width, left to right, as a MacBook draws them.
    static let widths: [OnboardingCornerKey: CGFloat] = [
        .function: 42, .control: 68, .option: 68, .command: 78,
    ]
    static let gap: CGFloat = 6
    static let inset: CGFloat = 12
    /// How long the lit keys stay up, then down, while they show what holding means.
    static let demonstrationBeat: TimeInterval = 1.4

    var body: some View {
        if let lit = keyboard.lit {
            corner(lit)
        } else {
            OnboardingKeycaps(keys: keyboard.keys, isHeld: keyboard.isHeld)
        }
    }

    private func corner(_ lit: Set<OnboardingCornerKey>) -> some View {
        let motion = MotionBudgetObserver.shared.budget
        return TimelineView(
            .animation(
                minimumInterval: Self.demonstrationBeat,
                paused: !keyboard.demonstrates || !attended || !motion.demonstrationMoves)
        ) { timeline in
            let beat = Int(timeline.date.timeIntervalSinceReferenceDate / Self.demonstrationBeat)
            let down =
                keyboard.isHeld || (keyboard.demonstrates && motion.demonstrationMoves && beat % 2 == 1)
            VStack(alignment: .leading, spacing: 4) {
                bracket(over: lit)
                HStack(spacing: Self.gap) {
                    ForEach(OnboardingCornerKey.allCases, id: \.self) { key in
                        OnboardingCornerKeycap(
                            key: key, isLit: lit.contains(key), isDown: lit.contains(key) && down)
                    }
                }
                .animation(MotionBudget.current().allowing(.easeInOut(duration: 0.16)), value: down)
            }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 8)
        .padding(.bottom, Self.inset)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.22)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                .white.opacity(0.08), lineWidth: 1)
        }
        .onWindowAttentionChange(includingMotionBudget: false) { attended = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            keyboard.bracket.map { "\($0.capitalized): \(keyboard.keys.joined(separator: " "))" } ?? "")
    }

    /// The label and bracket spanning the lit keys; kept in the layout when hidden so the keys never move.
    private func bracket(over lit: Set<OnboardingCornerKey>) -> some View {
        let keys = OnboardingCornerKey.allCases
        let first = keys.firstIndex(where: lit.contains) ?? 0
        let last = keys.lastIndex(where: lit.contains) ?? 0
        let leading = keys[..<first].reduce(0) { $0 + (Self.widths[$1] ?? 0) + Self.gap }
        let span = keys[first...last].reduce(-Self.gap) { $0 + (Self.widths[$1] ?? 0) + Self.gap }
        return VStack(spacing: 2) {
            Text(keyboard.bracket ?? " ")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Color(rgb: BrandPalette.Teal.inkOnFill))
                .padding(.vertical, 3)
                .padding(.horizontal, 9)
                .background(OnboardingInk.glow, in: .capsule)
                .shadow(color: OnboardingInk.teal.opacity(0.6), radius: 8)
            Path { path in
                path.move(to: CGPoint(x: 1, y: 9))
                path.addLine(to: CGPoint(x: 1, y: 4))
                path.addLine(to: CGPoint(x: span - 1, y: 4))
                path.addLine(to: CGPoint(x: span - 1, y: 9))
            }
            .stroke(OnboardingInk.glow, lineWidth: 1.6)
            .frame(width: span, height: 10)
        }
        .frame(width: span)
        .padding(.leading, leading)
        .opacity(keyboard.bracket == nil || lit.isEmpty ? 0 : 1)
    }
}

/// One keycap as a Mac prints it: the symbol at the top right, the name at the bottom left.
struct OnboardingCornerKeycap: View {
    let key: OnboardingCornerKey
    let isLit: Bool
    let isDown: Bool

    var body: some View {
        ZStack {
            Text(symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 6)
                .padding(.trailing, 8)
            Text(name)
                .font(.system(size: 10.5, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.bottom, 6)
                .padding(.leading, 8)
        }
        .foregroundStyle(isLit ? Color(rgb: BrandPalette.Teal.inkOnFill) : .white.opacity(0.72))
        .frame(width: OnboardingKeyboardCorner.widths[key] ?? 60, height: 62)
        // The glow and the key's edge are cast by the shape alone, so the printed words stay crisp.
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(face)
                .shadow(
                    color: isLit ? OnboardingInk.teal.opacity(isDown ? 1 : 0.75) : .clear,
                    radius: isDown ? 22 : 15
                )
                .shadow(
                    color: isLit ? Color(rgb: BrandPalette.Teal.deep) : .black, radius: 0, y: isDown ? 0 : 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isLit ? (isDown ? Color.white : OnboardingInk.glow) : .white.opacity(0.1),
                    lineWidth: isLit ? 2 : 1)
        }
        .offset(y: isDown ? 3 : 0)
    }

    private var face: LinearGradient {
        let colours: [Color] =
            isLit
            ? [OnboardingInk.teal, Color(rgb: BrandPalette.Teal.primary)]
            : [Color(rgb: BrandPalette.Onboarding.keyTop), Color(rgb: BrandPalette.Onboarding.keyBottom)]
        return LinearGradient(colors: colours, startPoint: .top, endPoint: .bottom)
    }

    private var symbol: String {
        switch key {
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    private var name: String {
        switch key {
        case .function: ""
        case .control: "control"
        case .option: "option"
        case .command: "command"
        }
    }
}

/// The field the first try fills: a placeholder, a ring with a meter and a clock while listening, or the words.
struct OnboardingTryField: View {
    let field: OnboardingField
    let isListening: Bool
    @State private var since = Date()

    var body: some View {
        HStack(spacing: 8) {
            words
            Rectangle().fill(Color(rgb: BrandPalette.Onboarding.caret)).frame(width: 2, height: 18)
            Spacer(minLength: 0)
            if isListening {
                OnboardingWaveform(wave: .talking, count: 9)
                    .foregroundStyle(Color(rgb: BrandPalette.Teal.primary))
                    .colorMultiply(Color(rgb: BrandPalette.Teal.primary))
                    .frame(width: 34, height: 18)
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(rgb: BrandPalette.Teal.deep))
                    .fixedSize()
            }
        }
        .font(BrandFont.display(size: 16, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.white.opacity(0.96), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(OnboardingInk.teal.opacity(isListening ? 0.55 : 0), lineWidth: 3)
                .padding(-3)
        }
        .shadow(color: .black.opacity(0.35), radius: 14, y: 12)
        .onChange(of: isListening) { since = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var words: some View {
        switch field {
        case .placeholder(let text):
            Text(text).foregroundStyle(Color(rgb: BrandPalette.Onboarding.fieldPlaceholder))
        case .filled(let text), .typing(let text):
            Text(text)
                .foregroundStyle(OnboardingInk.field)
                .truncationMode(.head)
                .padding(.horizontal, 3)
                .background(OnboardingInk.teal.opacity(0.3), in: .rect(cornerRadius: 4))
        }
    }

    private var label: String {
        switch field {
        case .placeholder(let text), .filled(let text), .typing(let text): text
        }
    }
}
