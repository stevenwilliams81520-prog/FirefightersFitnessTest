import SwiftUI
import Charts

struct RootView: View {
    @EnvironmentObject var engine: TestEngine

    var body: some View {
        NavigationStack {
            Group {
                switch engine.phase {
                case .setup: SetupView()
                case .running: RunningView()
                case .finished: ResultView()
                }
            }
            .navigationTitle("Firefighters Fitness Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var engine: TestEngine
    @State private var manualRest: Int?
    @State private var alertText: String?

    var body: some View {
        Form {
            Section("Your details") {
                LabeledContent("Age") {
                    TextField("Years", value: $engine.age, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Step height", selection: $engine.height) {
                    ForEach(StepHeight.allCases) { Text("\($0.rawValue) cm").tag($0) }
                }
                if let maxHR = engine.maxHR, let stopHR = engine.stopHR {
                    LabeledContent("Max heart rate", value: "\(maxHR) bpm")
                    LabeledContent("Test stops above", value: "\(stopHR) bpm")
                }
            }

            if let notice = engine.notice {
                Section { Text(notice).foregroundStyle(.red) }
            }

            Section {
                Label(engine.watchStatus, systemImage: "applewatch")
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Press Start Test on your watch. It reads your starting heart rate and begins the test. Press Record HR at the end of each stage. If your heart rate goes over the stop figure, the test ends and you get your score.")
            }

            Section {
                LabeledContent("Starting heart rate") {
                    TextField("bpm", value: $manualRest, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Button("Start without watch") {
                    if let error = engine.start(restingHR: manualRest) { alertText = error }
                }
            } header: {
                Text("No watch?")
            } footer: {
                Text("Type in each stage's heart rate yourself during the test.")
            }

            Section {
                Text("This app gives an estimate of aerobic fitness. Stop if you feel unwell, dizzy or in pain, or if the effort feels hard.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .alert("Can't start", isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertText ?? "")
        }
    }
}

// MARK: - Running

struct RunningView: View {
    @EnvironmentObject var engine: TestEngine
    @State private var confirmStop = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(engine.stageIndex.map { "Stage \($0 + 1)" } ?? "Get ready")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(engine.stageIndex.map { "\(Chester.stepRates[$0]) steps a minute" } ?? "Stage 1 starts soon")
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(timeString(engine.secondsLeftInStage))
                            .font(.title2.bold())
                            .monospacedDigit()
                        Text(engine.stageIndex == nil ? "to start" : "left in stage")
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, engine.elapsed / TestEngine.testLength))
                }
                .padding(.vertical, 4)
            }

            Section("Heart rate") {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(engine.liveHR.map { "\($0)" } ?? "--")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm").foregroundStyle(.secondary)
                    Spacer()
                    if let stopHR = engine.stopHR {
                        Text("Stops above \(stopHR)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Stage readings") { StageRows() }

            Section {
                Button("Stop test", role: .destructive) { confirmStop = true }
            }
        }
        .confirmationDialog("Stop the test now?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop and work out my score", role: .destructive) { engine.finish(.stopped) }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

struct StageRows: View {
    @EnvironmentObject var engine: TestEngine

    var body: some View {
        ForEach(0..<5, id: \.self) { i in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stage \(i + 1)").bold()
                    Text("\(Chester.stepRates[i]) steps/min · \(Int(engine.height.costs[i])) ml/kg/min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if engine.autoFilled.contains(i) {
                    Text("auto").font(.caption2).foregroundStyle(.secondary)
                }
                TextField("bpm", value: $engine.stageHR[i], format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit())
                    .frame(width: 72)
            }
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @EnvironmentObject var engine: TestEngine

    var body: some View {
        List {
            Section {
                if let r = engine.result {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Estimated VO₂max").foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%.1f", r.vo2max))
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("ml/kg/min").foregroundStyle(.secondary)
                        }
                        if r.vo2max >= Chester.standard {
                            Label("Meets the 42.3 standard", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(String(format: "%.1f below the 42.3 standard", Chester.standard - r.vo2max),
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if r.pointsUsed < 3 {
                            Text("Based on \(r.pointsUsed) stages. Three or more give a more reliable estimate.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if r.r2 < 0.9 {
                            Text("Your readings don't sit close to a straight line, so treat this result with caution.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("Not enough readings to estimate VO₂max. You need heart rates from at least two stages, rising from one stage to the next.")
                }
                if let notice = engine.notice {
                    Text(notice).font(.footnote)
                }
            }

            if let r = engine.result, let maxHR = engine.maxHR, let stopHR = engine.stopHR {
                Section {
                    ResultChart(costs: engine.height.costs, hrs: engine.stageHR, result: r,
                                maxHR: Double(maxHR), stopHR: Double(stopHR))
                        .frame(height: 260)
                        .padding(.vertical, 8)
                }
            }

            Section {
                StageRows()
            } header: {
                Text("Stage readings")
            } footer: {
                Text("You can correct a reading and the score updates.")
            }

            Section {
                LabeledContent("Starting heart rate", value: engine.restHR.map { "\($0) bpm" } ?? "–")
                LabeledContent("Step height", value: "\(engine.height.rawValue) cm")
                Button("New test") { engine.reset() }
            }
        }
    }
}

struct ResultChart: View {
    let costs: [Double]
    let hrs: [Int?]
    let result: Chester.Result
    let maxHR: Double
    let stopHR: Double

    private var points: [(x: Double, y: Double)] {
        (0..<5).compactMap { i in hrs[i].map { (x: costs[i], y: Double($0)) } }
    }

    var body: some View {
        let x0 = costs[0] - 4
        Chart {
            RuleMark(y: .value("Max", maxHR))
                .foregroundStyle(.primary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Max \(Int(maxHR))").font(.caption2)
                }
            RuleMark(y: .value("80%", stopHR))
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            RuleMark(x: .value("Standard", Chester.standard))
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            LineMark(x: .value("Oxygen cost", x0),
                     y: .value("Heart rate", result.intercept + result.slope * x0),
                     series: .value("Line", "fit"))
                .foregroundStyle(.red)
            LineMark(x: .value("Oxygen cost", result.vo2max),
                     y: .value("Heart rate", maxHR),
                     series: .value("Line", "fit"))
                .foregroundStyle(.red)
            ForEach(points.indices, id: \.self) { i in
                PointMark(x: .value("Oxygen cost", points[i].x), y: .value("Heart rate", points[i].y))
                    .foregroundStyle(.primary)
                    .symbolSize(70)
            }
            PointMark(x: .value("Oxygen cost", result.vo2max), y: .value("Heart rate", maxHR))
                .foregroundStyle(.red)
                .symbolSize(110)
        }
        .chartXAxisLabel("Oxygen cost (ml/kg/min)")
        .chartYAxisLabel("Heart rate")
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: .automatic(includesZero: false))
    }
}
