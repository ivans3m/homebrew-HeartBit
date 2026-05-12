import XCTest
@testable import HeartBit

final class ScheduleFirePolicyTests: XCTestCase {
    func testOfflineRetryAt_usesFiveMinutePeriod() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let retry = ScheduleFirePolicy.offlineRetryAt(now: now, defaultPeriodMinutes: 5)
        XCTAssertEqual(retry.timeIntervalSince(now), 300, accuracy: 0.001)
    }

    func testOfflineRetryAt_clampsPeriodToMaximumOneDay() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let retry = ScheduleFirePolicy.offlineRetryAt(now: now, defaultPeriodMinutes: 999_999)
        XCTAssertEqual(retry.timeIntervalSince(now), TimeInterval(1440 * 60), accuracy: 0.001)
    }

    func testOnTimePreservesExpectedWhenEnqueueFails() {
        let expected = Date(timeIntervalSince1970: 2_000_000)
        let nextStep = expected.addingTimeInterval(86_400)
        let result = ScheduleFirePolicy.nextExpectedOnTimeAfterEnqueueAttempt(
            enqueued: false,
            expected: expected,
            nextStep: nextStep
        )
        XCTAssertEqual(result, expected)
    }

    func testOnTimeAdvancesWhenEnqueueSucceeds() {
        let expected = Date(timeIntervalSince1970: 2_000_000)
        let nextStep = expected.addingTimeInterval(86_400)
        let result = ScheduleFirePolicy.nextExpectedOnTimeAfterEnqueueAttempt(
            enqueued: true,
            expected: expected,
            nextStep: nextStep
        )
        XCTAssertEqual(result, nextStep)
    }
}
