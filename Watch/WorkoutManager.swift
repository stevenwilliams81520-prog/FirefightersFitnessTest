import Foundation
import HealthKit

/// Runs a workout session on the watch so the heart rate sensor reports live, about once a second.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published var heartRate: Double = 0
    @Published var isRunning = false
    var onHeartRate: ((Double) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() async {
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .stepTraining
        config.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        heartRate = 0
        let date = Date()
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
        isRunning = true
    }

    func end(save: Bool) async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        isRunning = false
        session.end()
        try? await builder.endCollection(at: Date())
        if save {
            _ = try? await builder.finishWorkout()
        } else {
            builder.discardWorkout()
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let quantity = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in
            self.heartRate = bpm
            self.onHeartRate?(bpm)
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.isRunning = false }
    }
}
