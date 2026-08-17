import SwiftUI
import Charts
import PacerKit

/// Post-run summary: duration, cadence stats, on-beat %, cadence graph,
/// songs, and every musical target change.
struct SessionSummaryView: View {
    let summary: SessionRecorder.Summary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        statGrid
                        cadenceChart
                        if !summary.targetChanges.isEmpty {
                            targetChangeList
                        }
                        if !summary.songsPlayed.isEmpty {
                            songList
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Run Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(durationString, "DURATION")
            statTile(summary.averageCadence.map { "\(Int($0.rounded()))" } ?? "—", "AVG SPM")
            statTile(summary.peakCadence.map { "\(Int($0.rounded()))" } ?? "—", "PEAK SPM")
            statTile(summary.onBeatPercent.map { "\(Int($0.rounded()))%" } ?? "—", "ON BEAT")
            if let target = summary.requestedTargetSpm {
                statTile("\(target)", "TARGET SPM")
            }
            statTile("\(summary.targetChanges.count)", "MUSIC SHIFTS")
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cadenceChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CADENCE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            Chart {
                ForEach(Array(summary.samples.enumerated()), id: \.offset) { _, point in
                    if point.raw > 0 {
                        LineMark(
                            x: .value("Time", point.t),
                            y: .value("SPM", point.smoothed ?? point.raw)
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                    }
                }
                ForEach(Array(summary.targetChanges.enumerated()), id: \.offset) { _, change in
                    RuleMark(x: .value("Change", change.t))
                        .foregroundStyle(Theme.accentAlt.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYScale(domain: chartDomain)
            .frame(height: 180)
        }
        .pacerCard()
    }

    private var chartDomain: ClosedRange<Double> {
        let values = summary.samples.filter { $0.raw > 0 }.map { $0.smoothed ?? $0.raw }
        let lo = (values.min() ?? 120) - 10
        let hi = (values.max() ?? 190) + 10
        return lo...hi
    }

    private var targetChangeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MUSIC TARGET CHANGES")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(summary.targetChanges.enumerated()), id: \.offset) { _, change in
                HStack {
                    Text(change.t.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(change.targetSpm) BPM")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentAlt)
                    Spacer()
                    Text(change.reason)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .pacerCard()
    }

    private var songList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SONGS PLAYED")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.textTertiary)
            ForEach(Array(summary.songsPlayed.enumerated()), id: \.offset) { _, song in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(song.artist)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text(song.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .pacerCard()
    }

    private var durationString: String {
        let total = Int(summary.endedAt.timeIntervalSince(summary.startedAt))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
