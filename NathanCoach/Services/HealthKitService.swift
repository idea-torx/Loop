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

        var readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.respiratoryRate),
            HKObjectType.workoutType()
        ]
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }

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
        let yesterdayEvening = calendar.date(byAdding: .hour, value: -14, to: startOfToday) ?? startOfToday
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
        async let workoutsToday = workoutsCount(from: startOfToday, to: Date())
        async let workoutsThisWeek = workoutsCount(from: startOfWeek, to: Date())
        async let exerciseMinutes = quantitySum(
            type: HKQuantityType(.appleExerciseTime),
            unit: .minute(),
            from: startOfToday,
            to: Date()
        )
        async let hrv = quantityAverage(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli),
            from: yesterdayEvening,
            to: Date()
        )
        async let hrvBaseline = quantityAverage(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            unit: .secondUnit(with: .milli),
            from: thirtyDaysAgo,
            to: startOfToday
        )
        async let restingHR = quantityAverage(
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: startOfToday,
            to: Date()
        )
        async let restingHRBaseline = quantityAverage(
            type: HKQuantityType(.restingHeartRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: thirtyDaysAgo,
            to: startOfToday
        )
        async let respiratoryRate = quantityAverage(
            type: HKQuantityType(.respiratoryRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: startOfToday,
            to: Date()
        )
        async let respiratoryRateBaseline = quantityAverage(
            type: HKQuantityType(.respiratoryRate),
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: thirtyDaysAgo,
            to: startOfToday
        )
        async let sleep = sleepMinutes(from: yesterdayEvening, to: Date())
        async let sleepBaseline = averageSleepMinutes(from: thirtyDaysAgo, to: startOfToday)
        async let activitySummary = activitySummaryForToday()

        let hrvValue = await hrv
        let hrvBaselineValue = await hrvBaseline
        let restingValue = await restingHR
        let restingBaselineValue = await restingHRBaseline
        let respiratoryValue = await respiratoryRate
        let respiratoryBaselineValue = await respiratoryRateBaseline
        let sleepValue = await sleep
        let sleepBaselineValue = await sleepBaseline
        let rings = await activitySummary
        let activeEnergyValue = Int(await activeEnergy.rounded())
        let exerciseMinutesValue = Int(await exerciseMinutes.rounded())

        return HealthMetricSnapshot(
            steps: Int(await steps.rounded()),
            activeEnergy: rings.activeEnergy ?? activeEnergyValue,
            workoutsToday: await workoutsToday,
            workoutsThisWeek: await workoutsThisWeek,
            healthKitStatus: "Connected",
            sleepMinutes: sleepValue,
            sleepDeltaVs30d: delta(sleepValue, sleepBaselineValue),
            hrvMilliseconds: hrvValue,
            hrvDeltaVs30d: delta(hrvValue, hrvBaselineValue),
            restingHeartRate: restingValue,
            restingHeartRateDeltaVs30d: delta(restingValue, restingBaselineValue),
            respiratoryRate: respiratoryValue,
            respiratoryRateDeltaVs30d: delta(respiratoryValue, respiratoryBaselineValue),
            exerciseMinutes: rings.exerciseMinutes ?? exerciseMinutesValue,
            standHours: rings.standHours,
            movePercent: rings.movePercent
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

    private func quantityAverage(type: HKQuantityType, unit: HKUnit, from startDate: Date, to endDate: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sleepMinutes(from startDate: Date, to endDate: Date) async -> Int? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let total = (samples as? [HKCategorySample])?.reduce(0.0) { partial, sample in
                    guard Self.isAsleep(sample.value) else { return partial }
                    let start = max(sample.startDate, startDate)
                    let end = min(sample.endDate, endDate)
                    return partial + max(0, end.timeIntervalSince(start) / 60)
                } ?? 0
                continuation.resume(returning: total > 0 ? Int(total.rounded()) : nil)
            }
            store.execute(query)
        }
    }

    private func averageSleepMinutes(from startDate: Date, to endDate: Date) async -> Int? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: [.strictStartDate]
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let calendar = Calendar.current
                var byDay: [Date: Double] = [:]
                for sample in samples as? [HKCategorySample] ?? [] where Self.isAsleep(sample.value) {
                    let day = calendar.startOfDay(for: sample.endDate)
                    byDay[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
                }
                let nights = byDay.values.filter { $0 > 0 }
                guard !nights.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int((nights.reduce(0, +) / Double(nights.count)).rounded()))
            }
            store.execute(query)
        }
    }

    private func activitySummaryForToday() async -> (activeEnergy: Int?, exerciseMinutes: Int?, standHours: Int?, movePercent: Double?) {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            var components = calendar.dateComponents([.year, .month, .day], from: Date())
            components.calendar = calendar
            let predicate = HKQuery.predicateForActivitySummary(with: components)
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: (nil, nil, nil, nil))
                    return
                }
                let active = Int(summary.activeEnergyBurned.doubleValue(for: .kilocalorie()).rounded())
                let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let exercise = Int(summary.appleExerciseTime.doubleValue(for: .minute()).rounded())
                let stand = Int(summary.appleStandHours.doubleValue(for: .count()).rounded())
                continuation.resume(returning: (active, exercise, stand, goal > 0 ? Double(active) / goal : nil))
            }
            store.execute(query)
        }
    }

    nonisolated private static func isAsleep(_ value: Int) -> Bool {
        [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ].contains(value)
    }

    private func delta(_ value: Int?, _ baseline: Int?) -> Int? {
        guard let value, let baseline else { return nil }
        return value - baseline
    }

    private func delta(_ value: Double?, _ baseline: Double?) -> Double? {
        guard let value, let baseline else { return nil }
        return value - baseline
    }

    private var isAuthorizedForAnyWriteType: Bool {
        store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized
            || store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }
}
