import Foundation
import HealthKit

/// Saves a Chester Step Test result to Apple Health as a VO₂max reading.
enum HealthSaver {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission if needed, then saves the reading.
    /// Returns nil when saved, or a message explaining what went wrong.
    static func save(vo2max: Double, date: Date) async -> String? {
        guard isAvailable else { return "Apple Health isn't available on this device." }
        let type = HKQuantityType(.vo2Max)
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
        } catch {
            return "Couldn't ask for Health access: \(error.localizedDescription)"
        }
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            return "Health access is off. Turn it on in the Health app: tap your profile, then Apps, then Fitness Test, and allow VO2 Max."
        }
        let unit = HKUnit(from: "ml/kg*min")
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: (vo2max * 10).rounded() / 10),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeyVO2MaxTestType: NSNumber(value: 2), // 2 = submaximal exercise prediction (step test)
                HKMetadataKeyExternalUUID: UUID().uuidString
            ]
        )
        do {
            try await store.save(sample)
            return nil
        } catch {
            return "Couldn't save to Health: \(error.localizedDescription)"
        }
    }
}
