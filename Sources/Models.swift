import Foundation

enum MissedRunPolicy: String, Codable, CaseIterable, Identifiable {
    case skip = "Skip"
    case runOnce = "Run Once"
    case catchUp = "Catch Up"
    var id: String { rawValue }
}

enum JobStatus: String, Codable, Equatable {
    case idle
    case running
    case success
    case failed
    case delayed
    case needsAuth
}

enum ScheduleInterval: String, Codable, CaseIterable, Identifiable {
    case once = "Once"
    case defaultPeriod = "Default period"
    case minute = "Every minute"
    case fiveMinutes = "Every 5 minutes"
    case hour = "Every hour"
    case day = "Every day"
    case week = "Every week"
    case month = "Every month"
    case custom = "Custom"
    
    var id: String { rawValue }
}

enum JobExecutionMode: String, Codable, CaseIterable, Identifiable {
    case heartbit = "HeartBit"
    case cron = "Cron"
    var id: String { rawValue }
}

enum CronError: Error, LocalizedError {
    case invalidFormat
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Cron expression must have exactly 5 fields."
        case .invalidField(let field):
            return "Invalid cron field: \(field)"
        }
    }
}

struct CronExpression {
    let minutes: Set<Int>
    let hours: Set<Int>
    let daysOfMonth: Set<Int>
    let months: Set<Int>
    let daysOfWeek: Set<Int>
    let isDayOfMonthWildcard: Bool
    let isDayOfWeekWildcard: Bool

    init(_ expression: String) throws {
        let fields = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        guard fields.count == 5 else { throw CronError.invalidFormat }
        minutes = try Self.parseField(String(fields[0]), range: 0...59)
        hours = try Self.parseField(String(fields[1]), range: 0...23)
        daysOfMonth = try Self.parseField(String(fields[2]), range: 1...31)
        months = try Self.parseField(String(fields[3]), range: 1...12)
        daysOfWeek = try Self.parseField(String(fields[4]), range: 0...6)
        isDayOfMonthWildcard = String(fields[2]) == "*"
        isDayOfWeekWildcard = String(fields[4]) == "*"
    }

    private static func parseField(_ field: String, range: ClosedRange<Int>) throws -> Set<Int> {
        if field == "*" {
            return Set(range)
        }
        if field.hasPrefix("*/") {
            guard let step = Int(field.dropFirst(2)), step > 0 else {
                throw CronError.invalidField(field)
            }
            return Set(stride(from: range.lowerBound, through: range.upperBound, by: step))
        }
        var result = Set<Int>()
        for part in field.split(separator: ",") {
            if part.contains("-") {
                let bounds = part.split(separator: "-")
                guard bounds.count == 2,
                      let lo = Int(bounds[0]),
                      let hi = Int(bounds[1]),
                      range.contains(lo),
                      range.contains(hi),
                      lo <= hi else {
                    throw CronError.invalidField(field)
                }
                result.formUnion(lo...hi)
            } else {
                guard let value = Int(part), range.contains(value) else {
                    throw CronError.invalidField(field)
                }
                result.insert(value)
            }
        }
        return result
    }
}

struct HeartBitJob: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = "New Job"
    var command: String = ""
    var isEnabled: Bool = true
    
    var scheduleInterval: ScheduleInterval = .once
    var executionMode: JobExecutionMode = .heartbit
    var customCronExpression: String = ""
    var isImportedFromExternalCron: Bool = false
    var didConfirmHeartBitSwitch: Bool = false
    var startDate: Date = Date()
    var missedRunPolicy: MissedRunPolicy = .skip
    var isOnlineOnly: Bool = false

    var usesLoginShell: Bool = false
    var timeoutMinutes: Int? = nil

    var lastRunDate: Date?
    var nextExpectedRunDate: Date?
    var onlineRetryAfterDate: Date?
    
    var lastRunStatus: JobStatus = .idle
    var latestOutput: String = "" // Retained for fast viewing, but full logs go to file
    
    var isRunning: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case id, name, command, isEnabled, scheduleInterval, executionMode, customCronExpression, isImportedFromExternalCron, didConfirmHeartBitSwitch, startDate, missedRunPolicy, isOnlineOnly, usesLoginShell, timeoutMinutes, lastRunDate, nextExpectedRunDate, onlineRetryAfterDate, lastRunStatus, latestOutput
    }

    init(id: UUID = UUID(),
         name: String = "New Job",
         command: String = "",
         isEnabled: Bool = true,
         scheduleInterval: ScheduleInterval = .once,
         executionMode: JobExecutionMode = .heartbit,
         customCronExpression: String = "",
         isImportedFromExternalCron: Bool = false,
         didConfirmHeartBitSwitch: Bool = false,
         startDate: Date = Date(),
         missedRunPolicy: MissedRunPolicy = .skip,
         isOnlineOnly: Bool = false,
         usesLoginShell: Bool = false,
         timeoutMinutes: Int? = nil,
         lastRunDate: Date? = nil,
         nextExpectedRunDate: Date? = nil,
         onlineRetryAfterDate: Date? = nil,
         lastRunStatus: JobStatus = .idle,
         latestOutput: String = "",
         isRunning: Bool = false) {
        self.id = id
        self.name = name
        self.command = command
        self.isEnabled = isEnabled
        self.scheduleInterval = scheduleInterval
        self.executionMode = executionMode
        self.customCronExpression = customCronExpression
        self.isImportedFromExternalCron = isImportedFromExternalCron
        self.didConfirmHeartBitSwitch = didConfirmHeartBitSwitch
        self.startDate = startDate
        self.missedRunPolicy = missedRunPolicy
        self.isOnlineOnly = isOnlineOnly
        self.usesLoginShell = usesLoginShell
        self.timeoutMinutes = timeoutMinutes
        self.lastRunDate = lastRunDate
        self.nextExpectedRunDate = nextExpectedRunDate
        self.onlineRetryAfterDate = onlineRetryAfterDate
        self.lastRunStatus = lastRunStatus
        self.latestOutput = latestOutput
        self.isRunning = isRunning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "New Job"
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        scheduleInterval = try container.decodeIfPresent(ScheduleInterval.self, forKey: .scheduleInterval) ?? .once
        executionMode = try container.decodeIfPresent(JobExecutionMode.self, forKey: .executionMode) ?? .heartbit
        customCronExpression = try container.decodeIfPresent(String.self, forKey: .customCronExpression) ?? ""
        isImportedFromExternalCron = try container.decodeIfPresent(Bool.self, forKey: .isImportedFromExternalCron) ?? false
        didConfirmHeartBitSwitch = try container.decodeIfPresent(Bool.self, forKey: .didConfirmHeartBitSwitch) ?? false
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        missedRunPolicy = try container.decodeIfPresent(MissedRunPolicy.self, forKey: .missedRunPolicy) ?? .skip
        isOnlineOnly = try container.decodeIfPresent(Bool.self, forKey: .isOnlineOnly) ?? false
        usesLoginShell = try container.decodeIfPresent(Bool.self, forKey: .usesLoginShell) ?? false
        timeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .timeoutMinutes)
        lastRunDate = try container.decodeIfPresent(Date.self, forKey: .lastRunDate)
        nextExpectedRunDate = try container.decodeIfPresent(Date.self, forKey: .nextExpectedRunDate)
        onlineRetryAfterDate = try container.decodeIfPresent(Date.self, forKey: .onlineRetryAfterDate)
        lastRunStatus = try container.decodeIfPresent(JobStatus.self, forKey: .lastRunStatus) ?? .idle
        latestOutput = try container.decodeIfPresent(String.self, forKey: .latestOutput) ?? ""
        isRunning = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(scheduleInterval, forKey: .scheduleInterval)
        try container.encode(executionMode, forKey: .executionMode)
        try container.encode(customCronExpression, forKey: .customCronExpression)
        try container.encode(isImportedFromExternalCron, forKey: .isImportedFromExternalCron)
        try container.encode(didConfirmHeartBitSwitch, forKey: .didConfirmHeartBitSwitch)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(missedRunPolicy, forKey: .missedRunPolicy)
        try container.encode(isOnlineOnly, forKey: .isOnlineOnly)
        try container.encode(usesLoginShell, forKey: .usesLoginShell)
        try container.encodeIfPresent(timeoutMinutes, forKey: .timeoutMinutes)
        try container.encode(lastRunDate, forKey: .lastRunDate)
        try container.encode(nextExpectedRunDate, forKey: .nextExpectedRunDate)
        try container.encode(onlineRetryAfterDate, forKey: .onlineRetryAfterDate)
        try container.encode(lastRunStatus, forKey: .lastRunStatus)
        try container.encode(latestOutput, forKey: .latestOutput)
    }
}

/// JSON file wrapper for File ▸ Export from the Crono tab (plain `[HeartBitJob]` is also accepted on import).
struct HeartBitJobsExport: Codable {
    static let currentFormatVersion = 1
    var formatVersion: Int
    var jobs: [HeartBitJob]

    init(jobs: [HeartBitJob]) {
        self.formatVersion = Self.currentFormatVersion
        self.jobs = jobs
    }
}

func isValidCronExpression(_ expression: String) -> Bool {
    (try? CronExpression(expression)) != nil
}
