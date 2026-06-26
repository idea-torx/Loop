import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    private let store = HKHealthStore()
    private let authorizationRequestedKey = "loop_healthkit_authorization_requested"

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType()
        ]

        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.bodyMass),
            HKObjectType.workoutType()
        ]

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: authorizationRequestedKey)
            return isAuthorizedForAnyWriteType || UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        } catch {
            return false
        }
    }

    func authorizationStatus() -> (isOn: Bool, label: String) {
        guard isAvailable else { return (false, "Unavailable") }
        if isAuthorizedForAnyWriteType || UserDefaults.standard.bool(forKey: authorizationRequestedKey) {
            return (true, "Connected")
        }
        return (false, "Not requested")
    }

    func fetchTodaySnapshot() async -> HealthMetricSnapshot {
        guard isAvailable else {
            return HealthMetricSnapshot(steps: 0, activeEnergy: 0, workoutsToday: 0, workoutsThisWeek: 0, healthKitStatus: "Unavailable")
        }

        async let steps = quantitySum(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        )
        async let activeEnergy = quantitySum(
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            from: Calendar.current.startOfDay(for: Date()),
            to: Date()
        )
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? startOfToday
        async let workoutsToday = workoutsCount(from: startOfToday, to: Date())
        async let workoutsThisWeek = workoutsCount(from: startOfWeek, to: Date())

        return HealthMetricSnapshot(
            steps: Int(await steps.rounded()),
            activeEnergy: Int(await activeEnergy.rounded()),
            workoutsToday: await workoutsToday,
            workoutsThisWeek: await workoutsThisWeek,
            healthKitStatus: "Connected"
        )
    }

    private func quantitySum(type: HKQuantityType, unit: HKUnit, from startDate: Date, to endDate: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func workoutsCount(from startDate: Date, to endDate: Date) async -> Int {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    private var isAuthorizedForAnyWriteType: Bool {
        store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized
            || store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }
}
