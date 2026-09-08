import SwiftUI

/// A small "on air" panel showing which character is talking, with bars that
/// move to the actual loudness of the clip playing.
///
/// This replaced a subtitle bubble. Every line is a pre-recorded clip now and
/// `BanterAudioBank` carries no transcripts, so there were no words to show —
/// a waveform states what the app actually knows: someone is speaking, and
/// who. It is deliberately kept visually distinct from, and smaller than, the
/// real turn banner above it.
struct BanterWaveformView: View {
    let personaID: String
    /// Sampled once per tick rather than passed as a value, so the level can
    /// change far faster than the view hierarchy is rebuilt. See
    /// `SpeechQueueManager.currentBanterLevel`.
    let level: () -> Float

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barCount = 9
    private static let barWidth: CGFloat = 4
    private static let barSpacing: CGFloat = 3
    private static let maxBarHeight: CGFloat = 26
    private static let minBarHeight: CGFloat = 3

    /// 24 Hz. Fast enough to read as a voice, slow enough not to wake the
    /// display's full refresh rate for nine capsules on a screen that is
    /// otherwise sitting still in a car mount.
    private static let sampleInterval = 1.0 / 24.0

    var body: some View {
        HStack(spacing: 12) {
            Text(initial)
                .font(.system(.title3, design: .serif, weight: .black))
                .foregroundStyle(color)
                .frame(width: 36, height: 40)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("\(displayName.uppercased()) / ON AIR")
                    .font(RoadTheme.eyebrow)
                    .foregroundStyle(color)
                bars
                    .frame(height: Self.maxBarHeight, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .roadPanel()
        // The bars carry no information a screen reader can use, so the panel
        // announces itself as one phrase instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName) is speaking")
        .transition(.opacity)
    }

    @ViewBuilder
    private var bars: some View {
        if reduceMotion {
            // The panel appearing is what says someone is talking; the motion
            // is the optional half. Hold the shape still rather than dropping
            // to a bare label, so the layout doesn't change size mid-drive.
            barRow { index in
                scaled(0.5 * envelope(at: index))
            }
        } else {
            TimelineView(.periodic(from: .now, by: Self.sampleInterval)) { context in
                let amplitude = Double(level())
                let time = context.date.timeIntervalSinceReferenceDate
                barRow { index in
                    height(at: index, amplitude: amplitude, time: time)
                }
            }
        }
    }

    private func barRow(height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: Self.barWidth, height: height(index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func height(at index: Int, amplitude: Double, time: TimeInterval) -> CGFloat {
        // A travelling wave rather than a shared pulse: without the per-bar
        // phase offset all nine bars rise and fall together, which reads as a
        // blinking light instead of a voice.
        let phase = time * 7 - Double(index) * 0.55
        let ripple = 0.6 + 0.4 * sin(phase)
        return scaled(amplitude * envelope(at: index) * ripple)
    }

    /// Middle bars reach higher than the edges, so a loud moment reads as one
    /// shape rather than nine independent meters standing side by side.
    private func envelope(at index: Int) -> Double {
        let position = Double(index) / Double(Self.barCount - 1)
        return 0.45 + 0.55 * sin(.pi * position)
    }

    /// Maps a 0...1 fraction onto the bar's drawn height, clamped so a stray
    /// meter reading can't push a capsule outside the panel.
    private func scaled(_ fraction: Double) -> CGFloat {
        let clamped = min(1, max(0, fraction))
        return Self.minBarHeight + (Self.maxBarHeight - Self.minBarHeight) * CGFloat(clamped)
    }

    private var persona: VoicePersona? {
        VoicePersona.all.first { $0.id == personaID }
    }

    private var displayName: String {
        persona?.displayName ?? "Passenger"
    }

    private var initial: String {
        String(displayName.prefix(1))
    }

    private var color: Color {
        switch personaID {
        case "dan": return RoadTheme.accent
        case "harry": return RoadTheme.teal
        default: return RoadTheme.muted
        }
    }
}
