import Foundation

/// Pure scheduling helpers for on-time HeartBit fires and online-only retry timing (unit-tested).
internal enum ScheduleFirePolicy {
    internal static func offlineRetryAt(now: Date, defaultPeriodMinutes: Int) -> Date {
        let minutes = JobManager.normalizedDefaultPeriod(defaultPeriodMinutes)
        return now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// After an on-time fire, advance the calendar anchor only if enqueue succeeded; otherwise keep `expected` for offline retry.
    internal static func nextExpectedOnTimeAfterEnqueueAttempt(enqueued: Bool, expected: Date, nextStep: Date) -> Date {
        enqueued ? nextStep : expected
    }
}
