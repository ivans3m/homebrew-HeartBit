import Foundation

final class CrontabManager {
    static let shared = CrontabManager()

    private init() {}

    private let marker = "# heartbit:"

    func readRawCrontab() -> String {
        let lines = readCrontabLines()
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n")
    }

    func loadCronJobs() -> [HeartBitJob] {
        let lines = readCrontabLines()
        var jobs: [HeartBitJob] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(marker) {
                let uuidPart = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                i += 1
                guard i < lines.count else { break }
                let nextLine = lines[i]
                if let parsed = parseCronLine(nextLine) {
                    let jobId = UUID(uuidString: uuidPart) ?? UUID()
                    jobs.append(makeCronJob(id: jobId,
                                            name: inferName(from: parsed.command),
                                            command: parsed.command,
                                            cronExpression: parsed.cron,
                                            isEnabled: true,
                                            importedFromExternalCron: false))
                }
            } else if let parsed = parseCronLine(line) {
                jobs.append(makeCronJob(id: UUID(),
                                        name: inferName(from: parsed.command),
                                        command: parsed.command,
                                        cronExpression: parsed.cron,
                                        isEnabled: true,
                                        importedFromExternalCron: true))
            }
            i += 1
        }
        return jobs
    }

    func syncCronJobs(_ jobs: [HeartBitJob]) {
        let existingLines = readCrontabLines()
        let passthrough = extractPassthroughLines(from: existingLines)

        var merged: [String] = passthrough
        let cronJobs = jobs
            .filter { $0.executionMode == .cron && $0.isEnabled }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !merged.isEmpty, merged.last?.isEmpty == false {
            merged.append("")
        }

        for job in cronJobs {
            let cronExpression = normalizedCron(for: job)
            guard isValidCronExpression(cronExpression) else { continue }
            merged.append("\(marker)\(job.id.uuidString)")
            merged.append("\(cronExpression) \(job.command)")
        }

        let newPayload = Self.canonicalCrontabPayload(lines: merged)
        let currentPayload = Self.canonicalCrontabPayload(string: readRawCrontab())
        if newPayload == currentPayload {
            return
        }

        writeCrontabLines(merged)
    }

    /// Normalizes crontab text so we can skip redundant `crontab -` writes (fewer system prompts).
    private static func canonicalCrontabPayload(lines: [String]) -> String {
        canonicalCrontabPayload(string: lines.joined(separator: "\n"))
    }

    private static func canonicalCrontabPayload(string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Parsing helpers

    private func parseCronLine(_ line: String) -> (cron: String, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") { return nil }
        if trimmed.contains("=") && !trimmed.contains(" ") { return nil } // env var

        let fields = trimmed.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
        guard fields.count >= 6 else { return nil }
        let cron = fields[0..<5].joined(separator: " ")
        guard isValidCronExpression(cron) else { return nil }
        let command = String(fields[5])
        return (cron, command)
    }

    private func inferName(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "cronjob" }
        if let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first {
            return String(firstToken)
        }
        return "cronjob"
    }

    private func normalizedCron(for job: HeartBitJob) -> String {
        if !job.customCronExpression.isEmpty {
            return job.customCronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return JobManager.cronExpression(from: job.scheduleInterval, startDate: job.startDate)
    }

    private func makeCronJob(id: UUID,
                             name: String,
                             command: String,
                             cronExpression: String,
                             isEnabled: Bool,
                             importedFromExternalCron: Bool) -> HeartBitJob {
        HeartBitJob(
            id: id,
            name: name,
            command: command,
            isEnabled: isEnabled,
            scheduleInterval: .custom,
            executionMode: .cron,
            customCronExpression: cronExpression,
            isImportedFromExternalCron: importedFromExternalCron,
            startDate: Date(),
            missedRunPolicy: .skip,
            lastRunDate: nil,
            nextExpectedRunDate: nil,
            lastRunStatus: .idle,
            latestOutput: ""
        )
    }

    private func extractPassthroughLines(from lines: [String]) -> [String] {
        var result: [String] = []
        var skipNext = false
        for line in lines {
            if skipNext {
                skipNext = false
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(marker) {
                skipNext = true
                continue
            }
            result.append(line)
        }
        while result.last?.isEmpty == true {
            result.removeLast()
        }
        return result
    }

    // MARK: - Shell I/O

    private func readCrontabLines() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-l"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return []
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            if output.isEmpty { return [] }
            return output.components(separatedBy: .newlines)
        } catch {
            return []
        }
    }

    private func writeCrontabLines(_ lines: [String]) {
        var content = lines.joined(separator: "\n")
        if !content.isEmpty { content += "\n" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            if let data = content.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}
