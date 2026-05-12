import Foundation
import Observation
import AppKit
import Network
import AVFoundation

@Observable
class JobManager {
    static let shared = JobManager()
    
    var jobs: [HeartBitJob] = []
    var selectedJobId: UUID? = nil
    
    // Global Settings
    var isExecutionPaused: Bool = false {
        didSet {
            UserDefaults.standard.set(isExecutionPaused, forKey: "HB_IsExecutionPaused")
            DispatchQueue.main.async { [weak self] in
                self?.checkSchedules()
            }
        }
    }
    var showInDock: Bool = false {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: "HB_ShowInDock")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .heartbitRequestActivationPolicyUpdate, object: nil)
            }
        }
    }
    var logActivity: Bool = true {
        didSet { UserDefaults.standard.set(logActivity, forKey: "HB_LogActivity") }
    }
    var logRetentionDays: Int = 30 {
        didSet { UserDefaults.standard.set(logRetentionDays, forKey: "HB_LogRetentionDays") }
    }
    var defaultPeriodMinutes: Int = 5 {
        didSet {
            let normalized = Self.normalizedDefaultPeriod(defaultPeriodMinutes)
            if normalized != defaultPeriodMinutes {
                defaultPeriodMinutes = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: "HB_DefaultPeriodMinutes")
            rescheduleJobsUsingDefaultPeriod()
        }
    }
    
    var isAnyJobRunning: Bool { jobs.contains { $0.isRunning } }
    
    private let defaultsKey = "HeartBitJobs"
    private var timer: Timer?
    let logURL: URL
    
    // Custom Queue
    @ObservationIgnored private var executionQueue: [(UUID, Bool)] = []
    @ObservationIgnored private var isWorkingQueue: Bool = false
    @ObservationIgnored private var scheduledCronSync: DispatchWorkItem?
    @ObservationIgnored private var scheduledNetworkPathRecheck: DispatchWorkItem?
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private let networkMonitorQueue = DispatchQueue(label: "com.s3m.HeartBit.networkMonitor")
    
    init() {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryURL.appendingPathComponent("Logs/HeartBit")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logURL = logsDir.appendingPathComponent("HeartBit.log")
        
        self.isExecutionPaused = UserDefaults.standard.object(forKey: "HB_IsExecutionPaused") as? Bool ?? false
        self.showInDock = UserDefaults.standard.object(forKey: "HB_ShowInDock") as? Bool ?? false
        self.logActivity = UserDefaults.standard.object(forKey: "HB_LogActivity") as? Bool ?? true
        self.logRetentionDays = UserDefaults.standard.object(forKey: "HB_LogRetentionDays") as? Int ?? 30
        let savedDefaultPeriod = UserDefaults.standard.object(forKey: "HB_DefaultPeriodMinutes") as? Int ?? 5
        self.defaultPeriodMinutes = Self.normalizedDefaultPeriod(savedDefaultPeriod)
        
        loadJobs()
        mergeWithCrontab()
        setupNetworkMonitor()
        setupTimer()
        setupWakeListener()
        purgeOldLogs()
        logStartupCameraAuthorizationStatus()
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Logging
    
    func appendLog(_ message: String) {
        guard logActivity else { return }
        guard !shouldSkipFileLogging(for: message) else { return }
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

    private func shouldSkipFileLogging(for message: String) -> Bool {
        let normalized = message.lowercased()
        guard normalized.contains("pacer script") || normalized.contains("pacer") else { return false }
        let keepKeywords = ["error", "failed", "warn", "warning"]
        return !keepKeywords.contains(where: { normalized.contains($0) })
    }
    
    func clearLogs() {
        try? FileManager.default.removeItem(at: logURL)
    }

    func cameraAuthorizationStateLabel() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "authorized"
        case .denied, .restricted:
            return "denied/restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    func logStartupCameraAuthorizationStatus() {
        appendLog("Startup camera authorization status: \(cameraAuthorizationStateLabel())")
    }

    func requestCameraAccessFromApp() {
        let before = cameraAuthorizationStateLabel()
        appendLog("Camera access request initiated (current status: \(before))")

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            let after = self.cameraAuthorizationStateLabel()
            self.appendLog("Camera access request result: \(granted ? "granted" : "denied") (status now: \(after))")
        }
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

    /// Pretty-printed JSON for saving to a file from the Crono export action.
    func exportJobsFileData() throws -> Data {
        let payload = HeartBitJobsExport(jobs: jobs)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        return try enc.encode(payload)
    }

    /// Decodes jobs from export file data or a raw `[HeartBitJob]` JSON array (same shape as UserDefaults).
    static func decodeJobsForImport(from data: Data) throws -> [HeartBitJob] {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(HeartBitJobsExport.self, from: data) {
            return wrapped.jobs
        }
        return try decoder.decode([HeartBitJob].self, from: data)
    }

    /// Imports jobs from exported JSON. `replacingExisting` replaces the in-memory list; otherwise jobs are appended with fresh UUIDs.
    func importJobs(from data: Data, replacingExisting: Bool) throws {
        var imported = try Self.decodeJobsForImport(from: data)
        for i in imported.indices {
            imported[i].isRunning = false
        }
        if replacingExisting {
            jobs = imported
        } else {
            for var j in imported {
                j.id = UUID()
                jobs.append(j)
            }
        }
        saveJobs()
        syncCronJobsNow()
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
                    job.nextExpectedRunDate = advanceRun(for: job, from: job.startDate, passing: now)
                }
                jobs[idx] = job
            }
            
            if let expected = job.nextExpectedRunDate, now >= expected {
                if let retryAfter = job.onlineRetryAfterDate, now < retryAfter {
                    continue
                }
                if isExecutionPaused {
                    // Do not enqueue or apply missed-run / catch-up while paused. For recurring jobs,
                    // advance nextExpectedRunDate as if misses were skipped so resuming does not burst catch-up.
                    if job.scheduleInterval != .once {
                        job.nextExpectedRunDate = advanceRun(for: job, from: job.startDate, passing: now)
                        job.onlineRetryAfterDate = nil
                        jobs[idx] = job
                    }
                    continue
                }
                handleMissedAndRun(jobIndex: idx, now: now)
            }
        }
        saveJobs()
    }
    
    private func handleMissedAndRun(jobIndex: Int, now: Date) {
        let job = jobs[jobIndex]
        guard job.executionMode == .heartbit else { return }
        guard job.isEnabled else { return }
        guard !isExecutionPaused else { return }
        guard let expected = job.nextExpectedRunDate else { return }
        
        if job.scheduleInterval == .once {
            let id = job.id
            if enqueueOrDelayForOnline(jobIndex: jobIndex, jobId: id, now: now) {
                jobs[jobIndex].isEnabled = false
                jobs[jobIndex].nextExpectedRunDate = nil
            }
            return
        }
        
        guard let nextStep = calculateNextRun(for: job, from: expected) else { return }
        let intervalSeconds = nextStep.timeIntervalSince(expected)
        let missedTime = now.timeIntervalSince(expected)
        
        if missedTime > intervalSeconds * 1.5 {
            let missedCount = Int(missedTime / intervalSeconds)
            switch job.missedRunPolicy {
            case .skip:
                jobs[jobIndex].nextExpectedRunDate = advanceRun(for: job, from: job.startDate, passing: now)
            case .runOnce:
                let advanced = advanceRun(for: job, from: job.startDate, passing: now)
                if enqueueOrDelayForOnline(jobIndex: jobIndex, jobId: job.id, now: now) {
                    jobs[jobIndex].nextExpectedRunDate = advanced
                }
            case .catchUp:
                let advanced = advanceRun(for: job, from: job.startDate, passing: now)
                if job.isOnlineOnly {
                    guard enqueueOrDelayForOnline(jobIndex: jobIndex, jobId: job.id, now: now) else { return }
                    jobs[jobIndex].nextExpectedRunDate = advanced
                    for _ in 1...missedCount {
                        enqueueJob(id: job.id, isDryRun: false, fromScheduler: true)
                    }
                } else {
                    jobs[jobIndex].nextExpectedRunDate = advanced
                    for _ in 0...missedCount { enqueueJob(id: job.id, isDryRun: false, fromScheduler: true) }
                }
            }
        } else {
            let enqueued = enqueueOrDelayForOnline(jobIndex: jobIndex, jobId: job.id, now: now)
            jobs[jobIndex].nextExpectedRunDate = ScheduleFirePolicy.nextExpectedOnTimeAfterEnqueueAttempt(
                enqueued: enqueued,
                expected: expected,
                nextStep: nextStep
            )
        }
    }

    private func enqueueOrDelayForOnline(jobIndex: Int, jobId: UUID, now: Date) -> Bool {
        guard jobs.indices.contains(jobIndex) else { return false }
        let job = jobs[jobIndex]
        if !job.isOnlineOnly {
            jobs[jobIndex].onlineRetryAfterDate = nil
            enqueueJob(id: jobId, isDryRun: false, fromScheduler: true)
            return true
        }
        guard currentInternetOnlineState() else {
            let retryAt = ScheduleFirePolicy.offlineRetryAt(now: now, defaultPeriodMinutes: defaultPeriodMinutes)
            jobs[jobIndex].lastRunStatus = .delayed
            jobs[jobIndex].onlineRetryAfterDate = retryAt
            appendLog("DELAYED - \(job.name) (Online only enabled, internet offline; retry in \(defaultPeriodMinutes) minute(s) at \(retryAt.formatted(.iso8601)))")
            return false
        }
        if let retryAfter = jobs[jobIndex].onlineRetryAfterDate {
            appendLog("ONLINE RETRY - \(job.name) (internet is available; retry gate \(retryAfter.formatted(.iso8601)))")
        }
        jobs[jobIndex].onlineRetryAfterDate = nil
        enqueueJob(id: jobId, isDryRun: false, fromScheduler: true)
        return true
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
        case .defaultPeriod: return cal.date(byAdding: .minute, value: defaultPeriodMinutes, to: base)
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
        let cal = Calendar.current
        let now = Date()
        // Avoid scanning years minute-by-minute when `base` is stale.
        var cursor = max(base, now)
        if let minuteStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: cursor)) {
            cursor = minuteStart
        }
        if cursor < now {
            cursor = cal.date(byAdding: .minute, value: 1, to: cursor) ?? cursor.addingTimeInterval(60)
        }
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
        if current > target { return current }

        // Fast-forward when the anchor is far in the past (single-step `calculateNextRun(from: startDate)` would stay behind `now` and trigger immediate runs).
        switch job.scheduleInterval {
        case .once:
            return base
        case .minute, .fiveMinutes, .defaultPeriod:
            let stepMinutes: Int
            switch job.scheduleInterval {
            case .minute:
                stepMinutes = 1
            case .fiveMinutes:
                stepMinutes = 5
            case .defaultPeriod:
                stepMinutes = defaultPeriodMinutes
            default:
                stepMinutes = 1
            }
            let step = TimeInterval(stepMinutes * 60)
            let gap = target.timeIntervalSince(current)
            let n = Int(ceil(gap / step))
            return current.addingTimeInterval(TimeInterval(n) * step)
        case .hour, .day, .week, .month, .custom:
            var safety = 0
            while current <= target && safety < 500_000 {
                guard let next = calculateNextRun(for: job, from: current) else { return current }
                current = next
                safety += 1
            }
            return current
        }
    }

    /// Recomputes the next HeartBit fire time (e.g. after editing the schedule in the UI).
    func rescheduleHeartBitJob(at index: Int) {
        guard jobs.indices.contains(index), jobs[index].executionMode == .heartbit else { return }
        jobs[index].onlineRetryAfterDate = nil
        if jobs[index].scheduleInterval == .once {
            let start = jobs[index].startDate
            let now = Date()
            jobs[index].nextExpectedRunDate = now < start ? start : now
        } else {
            let job = jobs[index]
            jobs[index].nextExpectedRunDate = advanceRun(for: job, from: job.startDate, passing: Date())
        }
        saveJobs()
        checkSchedules()
    }

    /// When the user sets a clock time that falls on **today** but is not after the current moment (common with a time-only DatePicker that keeps today’s date), roll the calendar day forward by one so the anchor means the **next** occurrence—typically tomorrow at that time—instead of the past or “run immediately.”
    static func rollStartDateForwardIfTodayAlreadyPassed(_ date: Date, now: Date = Date()) -> Date {
        let cal = Calendar.current
        guard cal.isDate(date, inSameDayAs: now), date <= now else { return date }
        return cal.date(byAdding: .day, value: 1, to: date) ?? date
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
    
    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            self.scheduledNetworkPathRecheck?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.checkSchedules()
            }
            self.scheduledNetworkPathRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }
    
    private func currentInternetOnlineState() -> Bool {
        networkMonitor.currentPath.status == .satisfied
    }
    
    // MARK: - Execution Engine (Pipeline)
    
    /// - Parameter fromScheduler: When `true`, the run comes from HeartBit scheduling; skipped if the job is disabled or execution is globally paused. Manual "Run" / dry-run from the UI passes `false`.
    func enqueueJob(id: UUID, isDryRun: Bool = false, fromScheduler: Bool = false) {
        if fromScheduler {
            guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
            guard jobs[idx].isEnabled else { return }
            guard !isExecutionPaused else { return }
        }
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
        let usesLoginShell = jobs[idx].usesLoginShell
        let timeoutMinutes = Self.resolvedTimeoutMinutes(jobs[idx].timeoutMinutes)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = usesLoginShell ? ["-lc", command] : ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // Feed /dev/null so any interactive prompt (OAuth paste, `sudo`,
        // `read`) gets EOF immediately instead of stalling until the watchdog.
        if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
            process.standardInput = devNull
        }

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
            let timeoutNanos = UInt64(timeoutMinutes) * 60 * 1_000_000_000
            let watchDogTask = Task {
                try await Task.sleep(nanoseconds: timeoutNanos)
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
            let exitCode = Int(process.terminationStatus)
            let success = exitCode == 0 && !isTimedOut
            let resolvedStatus: JobStatus = isTimedOut
                ? .failed
                : Self.resolveStatus(exitCode: exitCode, output: outputStr)
            let finalOutput = isTimedOut
                ? "TIMED OUT AFTER \(timeoutMinutes) MINUTE(S). ABORTED."
                : outputStr

            await MainActor.run {
                if let updatedIdx = self.jobs.firstIndex(where: { $0.id == id }) {
                    if !isDryRun {
                        self.jobs[updatedIdx].lastRunDate = Date()
                        self.jobs[updatedIdx].lastRunStatus = resolvedStatus
                    }
                    self.jobs[updatedIdx].latestOutput = finalOutput
                    self.jobs[updatedIdx].isRunning = false
                    self.saveJobs()
                    let label = Self.logLabel(for: resolvedStatus, success: success)
                    self.appendLog("\(isDryRun ? "[DRY] " : "")\(label) - \(jobName)\(isTimedOut ? " (TIMEOUT)" : "")")
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

    /// Defaults to 10 minutes when the per-job timeout is absent or out of range.
    static func resolvedTimeoutMinutes(_ value: Int?) -> Int {
        guard let v = value, v > 0 else { return 10 }
        return min(v, 240)
    }

    /// Exit code 2 = auth required, 3 = permission required. Both surface as `needsAuth`
    /// so the UI can offer a Re-authenticate action. For third-party tools we don't control,
    /// fall back to known output substrings (`invalid_grant`, "Not authorized to send Apple events", ...).
    static func resolveStatus(exitCode: Int, output: String) -> JobStatus {
        switch exitCode {
        case 0:
            return .success
        case 2, 3:
            return .needsAuth
        default:
            if Self.outputLooksLikeAuthFailure(output) { return .needsAuth }
            return .failed
        }
    }

    private static let _authOutputSignatures = [
        "invalid_grant",
        "Not authorized to send Apple events",
        "errAEEventNotPermitted",
        "Token has been expired",
        "Token has expired",
        "401 Unauthorized",
        "Refresh token is missing",
    ]

    static func outputLooksLikeAuthFailure(_ output: String) -> Bool {
        guard !output.isEmpty else { return false }
        return _authOutputSignatures.contains(where: { output.contains($0) })
    }

    private static func logLabel(for status: JobStatus, success: Bool) -> String {
        switch status {
        case .needsAuth: return "NEEDS-AUTH"
        case .success: return "SUCCESS"
        case .failed: return "FAILED"
        case .delayed: return "DELAYED"
        case .running: return "RUNNING"
        case .idle: return success ? "SUCCESS" : "FAILED"
        }
    }

    // MARK: - Run job in Terminal

    /// Writes a one-shot `.command` script and opens it in the user's default
    /// terminal app so interactive auth flows (OAuth pastes, password prompts,
    /// `sudo`) can complete. Bypasses HeartBit's background process so stdin/stdout
    /// are real terminal handles.
    func runJobInTerminal(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("HeartBit/runs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let scriptURL = dir.appendingPathComponent("\(job.id.uuidString).command")

        let shebang = job.usesLoginShell ? "#!/bin/zsh -l" : "#!/bin/zsh"
        // Heredoc-safe: avoid escaping the user's command; write it raw on its own line.
        let body = """
        \(shebang)
        echo "HeartBit: running \(job.name) interactively"
        echo
        \(job.command)
        status=$?
        echo
        echo "--- Exit code: $status ---"
        echo "Press Return to close..."
        read _
        """

        do {
            try body.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            appendLog("ERROR - Could not write Run-in-Terminal script for \(job.name): \(error.localizedDescription)")
            return
        }

        NSWorkspace.shared.open(scriptURL)
        appendLog("RUN-IN-TERMINAL - \(job.name)")
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

    /// Writes minute/hour from `startDate` into a 5-field cron string, and optionally day/month/weekday when `updateCalendarFields` is true.
    /// Preserves fields that use steps (`/`), lists (`,`), or ranges (`-`).
    static func mergeStartDateIntoCronExpression(_ expression: String, startDate: Date, updateCalendarFields: Bool) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? cronExpression(from: .hour, startDate: startDate) : trimmed
        let parts = base.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return cronExpression(from: .hour, startDate: startDate)
        }
        var fields = parts
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: startDate)
        let minute = comps.minute ?? 0
        let hour = comps.hour ?? 0
        let day = comps.day ?? 1
        let month = comps.month ?? 1
        let weekday = ((comps.weekday ?? 1) + 6) % 7

        func patchField(_ index: Int, value: Int) {
            let f = fields[index]
            if f.contains("/") || f.contains(",") || f.contains("-") { return }
            if f == "*" || Int(f) != nil {
                fields[index] = "\(value)"
            }
        }

        patchField(0, value: minute)
        patchField(1, value: hour)
        if updateCalendarFields {
            patchField(2, value: day)
            patchField(3, value: month)
            patchField(4, value: weekday)
        }
        return fields.joined(separator: " ")
    }

    static func cronExpression(from interval: ScheduleInterval, startDate: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute, .hour, .day, .weekday], from: startDate)
        let minute = comps.minute ?? 0
        let hour = comps.hour ?? 0
        let day = comps.day ?? 1
        let weekday = ((comps.weekday ?? 1) + 6) % 7
        let defaultPeriod = JobManager.shared.defaultPeriodMinutes
        switch interval {
        case .once:
            return "\(minute) \(hour) \(day) * \(weekday)"
        case .minute:
            return "* * * * *"
        case .fiveMinutes:
            return "*/5 * * * *"
        case .defaultPeriod:
            return cronExpressionForDefaultPeriod(minutes: defaultPeriod, startDate: startDate)
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

    static func normalizedDefaultPeriod(_ minutes: Int) -> Int {
        min(max(1, minutes), 1440)
    }

    static func cronExpressionForDefaultPeriod(minutes: Int, startDate: Date) -> String {
        let normalized = normalizedDefaultPeriod(minutes)
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute, .hour], from: startDate)
        let minute = comps.minute ?? 0
        let hour = comps.hour ?? 0

        if normalized < 60 {
            return "*/\(normalized) * * * *"
        }
        if normalized % 60 == 0 {
            let hours = normalized / 60
            if hours < 24 {
                return "\(minute) */\(hours) * * *"
            }
            if hours % 24 == 0 {
                let days = max(1, min(hours / 24, 31))
                return "\(minute) \(hour) */\(days) * *"
            }
        }
        // Mixed day/hour/minute intervals cannot be represented exactly in 5-field cron.
        // Fallback to a stable daily time anchored to startDate.
        return "\(minute) \(hour) * * *"
    }

    private func rescheduleJobsUsingDefaultPeriod() {
        var shouldSyncCron = false
        for idx in jobs.indices {
            if jobs[idx].scheduleInterval == .defaultPeriod {
                jobs[idx].customCronExpression = Self.cronExpression(from: .defaultPeriod, startDate: jobs[idx].startDate)
                if jobs[idx].executionMode == .heartbit {
                    jobs[idx].nextExpectedRunDate = advanceRun(for: jobs[idx], from: jobs[idx].startDate, passing: Date())
                }
                shouldSyncCron = true
            }
        }
        if shouldSyncCron {
            saveJobs()
            checkSchedules()
            syncCronJobsNow()
        }
    }
}

extension Notification.Name {
    static let heartbitRequestActivationPolicyUpdate = Notification.Name("com.s3m.HeartBit.requestActivationPolicyUpdate")
}
