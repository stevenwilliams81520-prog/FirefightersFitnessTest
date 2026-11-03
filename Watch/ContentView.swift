import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        switch model.phase {
        case .idle: IdleView()
        case .reading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading your starting heart rate…")
                    .multilineTextAlignment(.center)
            }
        case .running: RunView()
        case .finished: DoneView()
        }
    }
}

struct IdleView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Fitness Test").font(.headline)
                if model.phoneReady {
                    Text("Stops above \(model.stopHR) bpm")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Enter your age in the iPhone app")
                        .font(.footnote).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button {
                    model.startTest()
                } label: {
                    Label("Start Test", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                if let message = model.message {
                    Text(message)
                        .font(.footnote).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear { model.refresh() }
    }
}

struct RunView: View {
    @EnvironmentObject var model: WatchModel
    @EnvironmentObject var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(model.stageLabel)
                    .font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workout.heartRate > 0 ? "\(Int(workout.heartRate.rounded()))" : "--")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("bpm").font(.caption2)
                }
                Button {
                    model.recordHR()
                } label: {
                    Text("Record HR").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Text(model.lastRecorded)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Button("End test", role: .destructive) { model.stopTest() }
                    .padding(.top, 8)
            }
        }
    }
}

struct DoneView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if model.stoppedAtThreshold {
                    Text("Target heart rate reached").font(.footnote).foregroundStyle(.orange)
                }
                if let vo2 = model.vo2 {
                    Text(String(format: "%.1f", vo2))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("VO₂max ml/kg/min").font(.caption2).foregroundStyle(.secondary)
                    Text(vo2 >= 42.3 ? "Meets 42.3 standard" : String(format: "%.1f below 42.3", 42.3 - vo2))
                        .font(.footnote)
                        .foregroundStyle(vo2 >= 42.3 ? Color.green : Color.orange)
                } else {
                    Text("Not enough stages for a score. See your iPhone.")
                        .multilineTextAlignment(.center)
                }
                Button("Done") { model.done() }.padding(.top, 8)
            }
        }
    }
}
