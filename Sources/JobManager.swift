import Foundation
import Observation
import AppKit

@Observable
class JobManager {
    static let shared = JobManager()
    
    var jobs: [HeartBitJob] = []
    var selectedJobId: UUID? = nil
    
    // Global Settings
    var isExecutionPaused: Bool = false {
        didSet { UserDefaults.standard.set(isExecutionPaused, forKey: "HB_IsExecutionPaused") }
    }
    var showInDock: Bool = false {
        didSet { UserDefaults.standard.set(showInDock, forKey: "HB_ShowInDock") }
    }
    var logActivity: Bool = true {
        didSet { UserDefaults.standard.set(logActivity, forKey: "HB_LogActivity") }
    }
    var logRetentionDays: Int = 30 {
        didSet { UserDefaults.standard.set(logRetentionDays, forKey: "HB_LogRetentionDays") }
    }
    
    var isAnyJobRunning: Bool { jobs.contains { $0.isRunning } }
    
    private let defaultsKey = "HeartBitJobs"
    private var timer: Timer?
    let logURL: URL
    
    // Custom Queue
    @ObservationIgnored private var executionQueue: [(UUID, Bool)] = []
    @ObservationIgnored private var isWorkingQueue: Bool = false
    @ObservationIgnored private var scheduledCronSync: DispatchWorkItem?
    
    init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryURL.appendingPathComponent("Logs/HeartBit")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("HeartBit.log")
        
        self.isExecutionPaused = UserDefaults.standard.object(forKey: "HB_IsExecutionPaused") as? Bool ?? false
        self.showInDock = UserDefaults.standard.object(forKey: "HB_ShowInDock") as? Bool ?? false
        self.logActivity = UserDefaults.standard.object(forKey: "HB_LogActivity") as? Bool ?? true
        self.logRetentionDays = UserDefaults.standard.object(forKey: "HB_LogRetentionDays") as? Int ?? 30
        
        loadJobs()
        mergeWithCrontab()
        setupTimer()
        setupWakeListener()
        purgeOldLogs()
    }
    
    // MARK: - Logging
    
    func appendLog(_ message: String) {
        guard logActivity else { return }
        let timestamp = Date().formatted(.iso8601)
        let logLine = "[\(timestamp)] \(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let data = logLine.data(using: .utf8) { handle.write(data) }
            handle.closeFile()
        } else {
            try? logLine.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
    
    func clearLogs() {
        try? FileManager.default.removeItem(at: logURL)
    }
    
    private func purgeOldLogs() {
        guard logRetentionDays > 0, logActivity else { return }
        guard let data = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -logRetentionDays, to: Date())!
        
        let lines = data.components(separatedBy: .newlines)
        var newLines = [String]()
        let isoFormatter = ISO8601DateFormatter()
        
        for line in lines {
            if line.starts(with: "[") {
                if let endBrack = line.firstIndex(of: "]") {
                    let dateStr = String(line[line.index(after: line.startIndex)..<endBrack])
                    if let date = isoFormatter.date(from: dateStr), date >= cutoff { newLines.append(line) }
                    else if isoFormatter.date(from: dateStr) == nil { newLines.append(line) }
                } else { newLines.append(line) }
            } else if !line.isEmpty { newLines.append(line) }
        }
        let filteredLog = newLines.joined(separator: "\n") + (newLines.isEmpty ? "" : "\n")
        try? filteredLog.write(to: logURL, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Data Management
    
    func loadJobs() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([HeartBitJob].self, from: data) {
            self.jobs = saved
        }
    }
    
    func saveJobs() {
        if let data = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
    
    func addJob(_ job: HeartBitJob) {
        var newJob = job
        newJob.nextExpectedRunDate = job.startDate
        jobs.append(newJob)
        saveJobs()
        syncCronJobsNow()
        appendLog("Added new job: \(newJob.name)")
    }
    
    func updateJob(_ job: HeartBitJob) {
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
            saveJobs()
            syncCronJobsNow()
        }
    }
    
    func deleteJob(id: UUID) {
        if let job = jobs.first(where: { $0.id == id }) {
            appendLog("Deleted job: \(job.name)")
        }
        jobs.removeAll { $0.id == id }
        saveJobs()
        syncCronJobsImmediately()
    }
    
    // MARK: - Scheduling
    
    func checkSchedules() {
        let now = Date()
        for idx in jobs.indices {
            var job = jobs[idx]
            guard job.isEnabled, job.executionMode == .heartbit else { continue }
            
            if job.nextExpectedRunDate == nil {
                if now < job.startDate {
                    job.nextExpectedRunDate = job.startDate
                } else if job.scheduleInterval == .once {
                    job.nextExpectedRunDate = now
                } else {
                    job.nextExpectedRunDate = calculateNextRun(for: job, from: job.startDate)
                }
                jobs[idx] = job
            }
            
            if let expected = job.nextExpectedRunDate, now >= expected {
                // If PAUSED globally, we advance the tracker but do NOT enqueue.
                // Actually, if paused, we should probably let time pass but queue them when unpaused?
                // The easiest is: do nothing. When unpaused, it will cleanly handle missed-run catchup!
                guard !isExecutionPaused else { continue }
                handleMissedAndRun(jobIndex: idx, now: now)
            }
        }
        saveJobs()
    }
    
    private func handleMissedAndRun(jobIndex: Int, now: Date) {
        let job = jobs[jobIndex]
        guard job.executionMode == .heartbit else { return }
        guard let expected = job.nextExpectedRunDate else { return }
        
        if job.scheduleInterval == .once {
            jobs[jobIndex].isEnabled = false
            jobs[jobIndex].nextExpectedRunDate = nil
            enqueueJob(id: job.id, isDryRun: false) // enqueue instead of execute direct
            return
        }
        
        guard let nextStep = calculateNextRun(for: job, from: expected) else { return }
        let intervalSeconds = nextStep.timeIntervalSince(expected)
        let missedTime = now.timeIntervalSince(expected)
        
        if missedTime > intervalSeconds * 1.5 {
            let missedCount = Int(missedTime / intervalSeconds)
            switch job.missedRunPolicy {
            case .skip:
                jobs[jobIndex].nextExpectedRunDate = advanceRun(for: job, from: expected, passing: now)
            case .runOnce:
                jobs[jobIndex].nextExpectedRunDate = advanceRun(for: job, from: expected, passing: now)
                enqueueJob(id: job.id, isDryRun: false)
            case .catchUp:
                jobs[jobIndex].nextExpectedRunDate = advanceRun(for: job, from: expected, passing: now)
                for _ in 0...missedCount { enqueueJob(id: job.id, isDryRun: false) }
            }
        } else {
            jobs[jobIndex].nextExpectedRunDate = nextStep
            enqueueJob(id: job.id, isDryRun: false)
        }
    }
    
    private func calculateNextRun(from base: Date, interval: ScheduleInterval) -> Date? {
        calculateNextRun(for: nil, from: base, intervalOverride: interval)
    }

    private func calculateNextRun(for job: HeartBitJob, from base: Date) -> Date? {
        calculateNextRun(for: job, from: base, intervalOverride: nil)
    }

    private func calculateNextRun(for job: HeartBitJob?, from base: Date, intervalOverride: ScheduleInterval?) -> Date? {
        let interval = intervalOverride ?? job?.scheduleInterval ?? .once
        let cal = Calendar.current
        switch interval {
        case .once: return nil
        case .minute: return cal.date(byAdding: .minute, value: 1, to: base)
        case .fiveMinutes: return cal.date(byAdding: .minute, value: 5, to: base)
        case .hour: return cal.date(byAdding: .hour, value: 1, to: base)
        case .day: return cal.date(byAdding: .day, value: 1, to: base)
        case .week: return cal.date(byAdding: .day, value: 7, to: base)
        case .month: return cal.date(byAdding: .month, value: 1, to: base)
        case .custom:
            return calculateNextRunFromCron(base: base, expression: job?.customCronExpression)
        }
    }

    private func calculateNextRunFromCron(base: Date, expression: String?) -> Date? {
        guard let expression else { return nil }
        guard let cron = try? CronExpression(expression) else { return nil }
        var cursor = base.addingTimeInterval(60)
        let cal = Calendar.current
        let maxIterations = 366 * 24 * 60
        for _ in 0..<maxIterations {
            let comps = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: cursor)
            guard let minute = comps.minute,
                  let hour = comps.hour,
                  let day = comps.day,
                  let month = comps.month,
                  let weekday = comps.weekday else {
                cursor = cursor.addingTimeInterval(60)
                continue
            }
            let cronWeekday = (weekday + 6) % 7
            if cron.minutes.contains(minute) &&
                cron.hours.contains(hour) &&
                cron.months.contains(month) &&
                cronDateMatch(day: day, cronWeekday: cronWeekday, cron: cron) {
                return cursor
            }
            cursor = cursor.addingTimeInterval(60)
        }
        return nil
    }

    private func cronDateMatch(day: Int, cronWeekday: Int, cron: CronExpression) -> Bool {
        let domMatch = cron.daysOfMonth.contains(day)
        let dowMatch = cron.daysOfWeek.contains(cronWeekday)

        if cron.isDayOfMonthWildcard && cron.isDayOfWeekWildcard { return true }
        if cron.isDayOfMonthWildcard { return dowMatch }
        if cron.isDayOfWeekWildcard { return domMatch }
        return domMatch || dowMatch
    }
    
    private func advanceRun(from base: Date, interval: ScheduleInterval, passing target: Date) -> Date {
        var current = base
        while current <= target {
            if let next = calculateNextRun(from: current, interval: interval) { current = next }
            else { break }
        }
        return current
    }

    private func advanceRun(for job: HeartBitJob, from base: Date, passing target: Date) -> Date {
        var current = base
        while current <= target {
            if let next = calculateNextRun(for: job, from: current) { current = next }
            else { break }
        }
        return current
    }
    
    // MARK: - Lifecycle
    
    private func setupTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkSchedules()
        }
        checkSchedules()
    }
    
    private func setupWakeListener() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { self?.checkSchedules() }
        }
    }
    
    // MARK: - Execution Engine (Pipeline)
    
    func enqueueJob(id: UUID, isDryRun: Bool = false) {
        if isDryRun { appendLog("Triggered Manual Dry-Run ID: \(id)") }
        executionQueue.append((id, isDryRun))
        processNextInQueue()
    }
    
    private func processNextInQueue() {
        guard !isWorkingQueue, !executionQueue.isEmpty else { return }
        isWorkingQueue = true
        let payload = executionQueue.removeFirst()
        
        Task {
            await executeRawJobAsync(id: payload.0, isDryRun: payload.1)
            isWorkingQueue = false
            processNextInQueue()
        }
    }
    
    private func executeRawJobAsync(id: UUID, isDryRun: Bool) async {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        
        await MainActor.run {
            jobs[idx].isRunning = true
            if !isDryRun {
                jobs[idx].lastRunStatus = .running
            }
            jobs[idx].latestOutput = ""
        }
        
        let jobName = jobs[idx].name
        let command = jobs[idx].command
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        actor TimeoutState {
            private var timedOut = false
            func markTimedOut() { timedOut = true }
            func value() -> Bool { timedOut }
        }
        let timeoutState = TimeoutState()
        var outputStr = ""
        
        do {
            try process.run()
            
            // Watchdog Timer
            let watchDogTask = Task {
                try await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000) // 10 minutes
                if process.isRunning {
                    process.terminate()
                    await timeoutState.markTimedOut()
                }
            }
            
            if let data = try pipe.fileHandleForReading.readToEnd(), let str = String(data: data, encoding: .utf8) {
                outputStr = str
            }
            process.waitUntilExit()
            watchDogTask.cancel() // Job completed
            
            let isTimedOut = await timeoutState.value()
            let success = process.terminationStatus == 0 && !isTimedOut
            let finalOutput = outputStr
            
            await MainActor.run {
                if let updatedIdx = self.jobs.firstIndex(where: { $0.id == id }) {
                    if !isDryRun {
                        self.jobs[updatedIdx].lastRunDate = Date()
                        self.jobs[updatedIdx].lastRunStatus = success ? .success : .failed
                    }
                    self.jobs[updatedIdx].latestOutput = isTimedOut ? "TIMED OUT AFTER 10 MINUTES. ABORTED." : finalOutput
                    self.jobs[updatedIdx].isRunning = false
                    self.saveJobs()
                    self.appendLog("\(isDryRun ? "[DRY] " : "")\(success ? "SUCCESS" : "FAILED") - \(jobName)\(isTimedOut ? " (TIMEOUT)" : "")")
                }
            }
        } catch {
            await MainActor.run {
                if let updatedIdx = self.jobs.firstIndex(where: { $0.id == id }) {
                    if !isDryRun {
                        self.jobs[updatedIdx].lastRunDate = Date()
                        self.jobs[updatedIdx].lastRunStatus = .failed
                    }
                    let errStr = "Error: \(error.localizedDescription)"
                    self.jobs[updatedIdx].latestOutput = errStr
                    self.jobs[updatedIdx].isRunning = false
                    self.saveJobs()
                    self.appendLog("\(isDryRun ? "[DRY] " : "")ERROR - \(jobName): \(errStr)")
                }
            }
        }
    }

    /// Coalesces rapid edits into fewer `crontab` writes (reduces repeated macOS permission prompts).
    func syncCronJobsNow() {
        scheduledCronSync?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            CrontabManager.shared.syncCronJobs(self.jobs)
        }
        scheduledCronSync = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func syncCronJobsImmediately() {
        scheduledCronSync?.cancel()
        CrontabManager.shared.syncCronJobs(jobs)
    }

    private func mergeWithCrontab() {
        let cronJobs = CrontabManager.shared.loadCronJobs()
        guard !cronJobs.isEmpty else { return }

        for cronJob in cronJobs {
            if let idx = jobs.firstIndex(where: { $0.id == cronJob.id }) {
                jobs[idx].executionMode = .cron
                jobs[idx].scheduleInterval = .custom
                jobs[idx].customCronExpression = cronJob.customCronExpression
                jobs[idx].isEnabled = cronJob.isEnabled
                jobs[idx].isImportedFromExternalCron = cronJob.isImportedFromExternalCron
                if jobs[idx].name.isEmpty || jobs[idx].name == "New Job" {
                    jobs[idx].name = cronJob.name
                }
                jobs[idx].command = cronJob.command
                continue
            }

            if let existingBySignature = jobs.firstIndex(where: {
                $0.executionMode == .cron &&
                $0.command == cronJob.command &&
                $0.customCronExpression == cronJob.customCronExpression
            }) {
                jobs[existingBySignature].isEnabled = true
                jobs[existingBySignature].isImportedFromExternalCron = cronJob.isImportedFromExternalCron
                continue
            }

            jobs.append(cronJob)
        }

        saveJobs()
        syncCronJobsImmediately()
    }

    static func cronExpression(from interval: ScheduleInterval, startDate: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute, .hour, .day, .weekday], from: startDate)
        let minute = comps.minute ?? 0
        let hour = comps.hour ?? 0
        let day = comps.day ?? 1
        let weekday = ((comps.weekday ?? 1) + 6) % 7
        switch interval {
        case .once:
            return "\(minute) \(hour) \(day) * \(weekday)"
        case .minute:
            return "* * * * *"
        case .fiveMinutes:
            return "*/5 * * * *"
        case .hour:
            return "\(minute) * * * *"
        case .day:
            return "\(minute) \(hour) * * *"
        case .week:
            return "\(minute) \(hour) * * \(weekday)"
        case .month:
            return "\(minute) \(hour) \(day) * *"
        case .custom:
            return "* * * * *"
        }
    }
}
