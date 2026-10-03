import Foundation
import SwiftUI
import GestureIMECore

struct ContentView: View {
    @StateObject private var model = HarnessViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controls
                    GesturePad(model: model)
                        .frame(height: 320)
                    liveState
                    metrics
                }
                .padding()
            }
            .navigationTitle("Gesture Harness")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Bindings", selection: $model.mode) {
                ForEach(HarnessViewModel.ProfileMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Trial", selection: $model.trialIntent) {
                ForEach(HarnessViewModel.TrialIntent.allCases) { intent in
                    Text(intent.rawValue).tag(intent)
                }
            }

            slider("Dead zone", value: $model.deadZone, range: 0.05...0.35)
            slider("Stage 1", value: $model.stage1Distance, range: 0.20...0.90)
            slider("Stage 2", value: $model.stage2Distance, range: 0.20...1.20)
            slider("Hysteresis", value: $model.hysteresis, range: 0...20, suffix: "°")
        }
    }

    private func slider(
        _ title: String,
        value: SwiftUI.Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f%@", value.wrappedValue, suffix))
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    private var liveState: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            row("Path", model.pathText)
            row("Candidate", model.candidateText)
            row("Eligible", model.eligibleDirections.map { $0.rawValue.uppercased() }.joined(separator: " "))
            row("Terminal", model.terminalText)
            row("Actions", model.actionLog.isEmpty ? "—" : model.actionLog.joined(separator: ", "))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Measurement").font(.headline)
            HStack {
                metric("Trials", "\(model.trials)")
                metric("Stage 2", model.stage2RateText)
                metric("Accidental", model.accidentalRateText)
            }
            if model.trialIntent == .singleStage {
                Text("Single-stage trials: \(model.singleStageTrials) • accidental stage 2: \(model.accidentalStage2)")
                    .font(.footnote)
            } else {
                Text("Target successes: \(model.deliberateStage2Success)/\(model.deliberateStage2Trials) (\(model.deliberateSuccessRateText))")
                    .font(.footnote)
            }
            HStack {
                Button("Clear trace") { model.resetVisuals() }
                Button("Reset metrics") { model.resetMetrics() }
                ShareLink(item: model.measurementSummary) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value).monospaced()
        }
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3).monospacedDigit()
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GesturePad: View {
    @ObservedObject var model: HarnessViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary)

                Canvas { context, _ in
                    if model.trace.count > 1 {
                        var trace = Path()
                        trace.move(to: model.trace[0])
                        for point in model.trace.dropFirst() { trace.addLine(to: point) }
                        context.stroke(trace, with: .color(.primary), lineWidth: 3)
                    }

                    for point in model.commitAnchors {
                        context.fill(Path(ellipseIn: markerRect(point, radius: 7)), with: .color(.primary))
                    }

                    if let anchor = model.anchor {
                        context.stroke(Path(ellipseIn: markerRect(anchor, radius: 11)), with: .color(.primary), lineWidth: 2)
                    }
                }

                if let anchor = model.anchor {
                    ForEach(model.eligibleDirections, id: \.self) { direction in
                        Text(direction.rawValue.uppercased())
                            .font(.caption.bold())
                            .padding(5)
                            .background(.thinMaterial, in: Capsule())
                            .position(position(for: direction, anchor: anchor, radius: 68))
                    }
                }

                Text("あ")
                    .font(.system(size: 52, weight: .semibold))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        model.beginIfNeeded(start: value.startLocation, keySize: proxy.size)
                        model.move(to: value.location)
                    }
                    .onEnded { value in
                        model.end(at: value.location)
                    }
            )
        }
        .accessibilityLabel("Gesture test pad")
    }

    private func markerRect(_ point: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }

    private func position(for direction: Direction8, anchor: CGPoint, radius: CGFloat) -> CGPoint {
        let vector: (CGFloat, CGFloat)
        switch direction {
        case .n: vector = (0, -1)
        case .ne: vector = (0.707, -0.707)
        case .e: vector = (1, 0)
        case .se: vector = (0.707, 0.707)
        case .s: vector = (0, 1)
        case .sw: vector = (-0.707, 0.707)
        case .w: vector = (-1, 0)
        case .nw: vector = (-0.707, -0.707)
        }
        return CGPoint(x: anchor.x + vector.0 * radius, y: anchor.y + vector.1 * radius)
    }
}
