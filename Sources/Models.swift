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
}

enum ScheduleInterval: String, Codable, CaseIterable, Identifiable {
    case once = "Once"
    case minute = "Every minute"
    case fiveMinutes = "Every 5 minutes"
    case hour = "Every hour"
    case day = "Every day"
    case week = "Every week"
    case month = "Every month"
    
    var id: String { rawValue }
}

struct HeartBitJob: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = "New Job"
    var command: String = ""
    var isEnabled: Bool = true
    
    var scheduleInterval: ScheduleInterval = .once
    var startDate: Date = Date()
    var missedRunPolicy: MissedRunPolicy = .skip
    
    var lastRunDate: Date?
    var nextExpectedRunDate: Date?
    
    var lastRunStatus: JobStatus = .idle
    var latestOutput: String = "" // Retained for fast viewing, but full logs go to file
    
    var isRunning: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case id, name, command, isEnabled, scheduleInterval, startDate, missedRunPolicy, lastRunDate, nextExpectedRunDate, lastRunStatus, latestOutput
    }
}
