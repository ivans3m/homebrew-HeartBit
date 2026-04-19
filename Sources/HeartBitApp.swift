import SwiftUI
import AppKit

private enum ActivationPolicyDebouncer {
    private static var pending: DispatchWorkItem?

    static func schedule(delay: TimeInterval = 0.22, _ body: @escaping () -> Void) {
        pending?.cancel()
        let item = DispatchWorkItem { body() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

@main
struct HeartBitApp: App {
    @Environment(\.openWindow) private var openWindow
    var jobManager = JobManager.shared
    
    var body: some Scene {
        MenuBarExtra {
            Group {
            if jobManager.isExecutionPaused {
                Text("Execution is Paused")
                    .foregroundColor(.secondary)
                Divider()
            }
            
            let allJobs = jobManager.jobs
            
            let pastBuckets = allJobs.filter { bucket(for: $0) == .past }.sorted { 
                let d0 = $0.lastRunDate ?? $0.startDate
                let d1 = $1.lastRunDate ?? $1.startDate
                return (d0 == d1) ? ($0.name < $1.name) : (d0 < d1)
            }
            let completedBuckets = allJobs.filter { bucket(for: $0) == .todayCompleted }.sorted { 
                let d0 = $0.lastRunDate ?? $0.startDate
                let d1 = $1.lastRunDate ?? $1.startDate
                return (d0 == d1) ? ($0.name < $1.name) : (d0 < d1)
            }
            let upcomingBuckets = allJobs.filter { bucket(for: $0) == .todayUpcoming }.sorted { 
                let d0 = $0.nextExpectedRunDate ?? $0.startDate
                let d1 = $1.nextExpectedRunDate ?? $1.startDate
                return (d0 == d1) ? ($0.name < $1.name) : (d0 < d1)
            }
            let futureBuckets = allJobs.filter { bucket(for: $0) == .future }.sorted { 
                let d0 = $0.nextExpectedRunDate ?? $0.startDate
                let d1 = $1.nextExpectedRunDate ?? $1.startDate
                return (d0 == d1) ? ($0.name < $1.name) : (d0 < d1)
            }
            
            if !pastBuckets.isEmpty {
                ForEach(pastBuckets) { job in
                    MenuJobRow(job: job, bucket: .past) { openJobSettings(id: job.id) }
                }
                Divider()
            }
            
            if !completedBuckets.isEmpty {
                ForEach(completedBuckets) { job in
                    MenuJobRow(job: job, bucket: .todayCompleted) { openJobSettings(id: job.id) }
                }
            }
            
            if !completedBuckets.isEmpty && !upcomingBuckets.isEmpty {
                Divider()
            }
            
            if !upcomingBuckets.isEmpty {
                ForEach(upcomingBuckets) { job in
                    MenuJobRow(job: job, bucket: .todayUpcoming) { openJobSettings(id: job.id) }
                }
            }
            
            if (!completedBuckets.isEmpty || !upcomingBuckets.isEmpty) && !futureBuckets.isEmpty {
                Divider()
            }
            
            if !futureBuckets.isEmpty {
                ForEach(futureBuckets) { job in
                    MenuJobRow(job: job, bucket: .future) { openJobSettings(id: job.id) }
                }
            }
            
            if pastBuckets.isEmpty && completedBuckets.isEmpty && upcomingBuckets.isEmpty && futureBuckets.isEmpty {
                Text("No Jobs Scheduled")
            }
            Divider()
            
            Button("Settings") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
                updateActivationPolicy()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            }
            .onAppear { updateActivationPolicy() }
            .onReceive(NotificationCenter.default.publisher(for: .heartbitRequestActivationPolicyUpdate)) { _ in
                updateActivationPolicy()
            }
        } label: {
            if jobManager.isExecutionPaused {
                Image(systemName: "pause.circle")
            } else {
                Image(systemName: "heart")
                    .symbolEffect(.pulse, isActive: jobManager.isAnyJobRunning)
            }
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: jobManager.isExecutionPaused) { _, paused in
            updateExecutionStateIcon(paused: paused)
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(jobManager)
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.updateActivationPolicy() }
                }
                .onAppear { 
                    self.updateActivationPolicy()
                    self.updateExecutionStateIcon(paused: jobManager.isExecutionPaused)
                }
        }
    }
    
    private func updateExecutionStateIcon(paused: Bool) {
        if paused {
            NSApp.applicationIconImage = NSImage(named: "PauseIcon")
        } else {
            NSApp.applicationIconImage = nil // Resets to default bundled icon
        }
    }
    
    private func updateActivationPolicy() {
        if jobManager.showInDock {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
            return
        }
        let hasCandidateWindow = NSApp.windows.contains { window in
            guard window.className != "NSStatusBarWindow" else { return false }
            if window.isVisible { return true }
            if window.title == "Settings" { return true }
            return false
        }
        if hasCandidateWindow {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
        ActivationPolicyDebouncer.schedule {
            guard !self.jobManager.showInDock else { return }
            let stillHasWindow = NSApp.windows.contains { window in
                guard window.className != "NSStatusBarWindow" else { return false }
                return window.isVisible || window.title == "Settings"
            }
            if !stillHasWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    private func openJobSettings(id: UUID) {
        jobManager.selectedJobId = id 
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
        updateActivationPolicy()
    }
}

enum JobBucket {
    case past
    case todayCompleted
    case todayUpcoming
    case future
}

func getTargetDate(for job: HeartBitJob) -> Date {
    let cal = Calendar.current
    if let last = job.lastRunDate, cal.isDateInToday(last) {
        if job.isEnabled, let next = job.nextExpectedRunDate, cal.isDateInToday(next) {
            return next
        }
        return last
    }
    return job.nextExpectedRunDate ?? job.lastRunDate ?? job.startDate
}

func bucket(for job: HeartBitJob) -> JobBucket {
    let target = getTargetDate(for: job)
    let cal = Calendar.current
    if cal.isDateInToday(target) {
        if job.isRunning { return .todayUpcoming }
        if let last = job.lastRunDate, cal.isDateInToday(last) {
            if job.isEnabled, let next = job.nextExpectedRunDate, cal.isDateInToday(next) {
                return .todayUpcoming
            }
            return .todayCompleted
        }
        return .todayUpcoming
    }
    
    let now = Date()
    // Compare dates conceptually avoiding precise timezone slips if possible, but standard is fine
    if target < now { return .past }
    return .future
}

struct MenuJobStyle {
    let color: Color
    let iconName: String
    let iconColor: Color
    let dateStr: String
}

func styling(for job: HeartBitJob, bucket: JobBucket) -> MenuJobStyle {
    let grey: Color = .secondary
    let black: Color = .primary
    
    let isGreyText = !job.isEnabled || bucket == .past || bucket == .todayCompleted
    let textColor = isGreyText ? grey : black
    
    var dateString = ""
    let showDate = (bucket == .past || bucket == .future)
    let displayDate = getTargetDate(for: job)
    
    if showDate {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd/MM"
        dateString = fmt.string(from: displayDate)
    } else {
        dateString = displayDate.formatted(date: .omitted, time: .shortened)
    }
    
    let isMissed = job.isEnabled && !job.isRunning && (job.nextExpectedRunDate != nil && job.nextExpectedRunDate! < Date())
    
    var icon = ""
    var iconCol = grey

    if !job.isEnabled {
        icon = "pause.circle"
    } else if job.executionMode == .cron {
        icon = "circle.dotted"
        iconCol = grey
    } else if job.isRunning {
        icon = "arrow.triangle.2.circlepath"
        iconCol = .yellow
    } else if isMissed {
        icon = "circle.fill"
        iconCol = .yellow
    } else if bucket == .past || bucket == .todayCompleted {
        icon = "circle.fill"
        iconCol = (job.lastRunStatus == .success) ? .green : ((job.lastRunStatus == .failed) ? .red : grey)
    } else {
        icon = "circle"
    }
    
    return MenuJobStyle(color: textColor, iconName: icon, iconColor: iconCol, dateStr: dateString)
}

struct MenuJobRow: View {
    let job: HeartBitJob
    let bucket: JobBucket
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            let style = styling(for: job, bucket: bucket)
            (Text(Image(systemName: style.iconName))
                .foregroundColor(style.iconColor)
                .font(.system(size: 10))
            + Text("  \(style.dateStr)  \(job.name)")
                .foregroundColor(style.color))
        }
    }
}
