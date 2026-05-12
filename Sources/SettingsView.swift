import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

enum SettingsSelection: Hashable {
    case about
    case globalSettings
    case cron
    case cronTab
    case job(UUID)
}

struct SettingsView: View {
    @Environment(JobManager.self) private var jobManager
    @State private var selection: SettingsSelection? = .globalSettings
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("App") {
                    NavigationLink(value: SettingsSelection.about) {
                        Label("About HeartBit", systemImage: "info.circle")
                    }
                    NavigationLink(value: SettingsSelection.globalSettings) {
                        Label("Global Settings", systemImage: "gear")
                    }
                    NavigationLink(value: SettingsSelection.cron) {
                        Label("Crono", systemImage: "terminal")
                    }
                }
                
                Section("Jobs") {
                    let sortedSidebarJobs = jobManager.jobs.sorted {
                        let date0 = $0.nextExpectedRunDate ?? $0.startDate
                        let date1 = $1.nextExpectedRunDate ?? $1.startDate
                        if date0 == date1 {
                            return $0.name < $1.name
                        }
                        return date0 < date1
                    }
                    ForEach(sortedSidebarJobs) { job in
                        NavigationLink(value: SettingsSelection.job(job.id)) {
                            HStack {
                                Image(systemName: sidebarIcon(for: job))
                                    .font(.caption2)
                                    .foregroundStyle(sidebarIconColor(for: job))
                                Text(job.name)
                                    .lineLimit(1)
                                Spacer()
                                if !job.isEnabled {
                                    Image(systemName: "pause.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                let resolvedDate = job.nextExpectedRunDate ?? (job.lastRunDate ?? job.startDate)
                                Text(formatSidebarDate(resolvedDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(action: { addNewJob() }) {
                        Label("Add New Job", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 250, max: 350)
            .navigationTitle("HeartBit")
        } detail: {
            switch selection {
            case .about:
                AboutView()
            case .globalSettings:
                GlobalSettingsView()
            case .cron:
                CronJobsView(selection: $selection)
            case .cronTab:
                CronTabView()
            case .job(let id):
                JobDetailView(jobId: id, selection: $selection)
            case .none:
                Text("Select an item")
            }
        }
        .frame(minWidth: 800, minHeight: 650)
        .onChange(of: jobManager.selectedJobId) { _, newValue in
            if let id = newValue {
                selection = .job(id)
                jobManager.selectedJobId = nil
            }
        }
    }
    
    private func addNewJob(at date: Date? = nil) {
        var newJob = HeartBitJob(name: "New Job")
        if let d = date { newJob.startDate = d }
        else {
            let now = Date()
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: now)
            let period = JobManager.normalizedDefaultPeriod(jobManager.defaultPeriodMinutes)
            comps.minute = ((comps.minute ?? 0) / period) * period + (period * 2) // +1 period buffer + up to next period
            if let nextSlot = cal.date(from: comps) { newJob.startDate = nextSlot }
        }
        jobManager.addJob(newJob)
        selection = .job(newJob.id)
    }
}

private func sidebarIcon(for job: HeartBitJob) -> String {
    if job.executionMode == .cron { return "circle.dotted" }
    if !job.isEnabled { return "pause.circle" }
    if job.isRunning { return "arrow.triangle.2.circlepath" }
    if job.lastRunStatus == .delayed { return "clock.badge.exclamationmark" }
    if job.lastRunStatus == .success { return "circle.fill" }
    if job.lastRunStatus == .failed { return "circle.fill" }
    return "circle"
}

private func sidebarIconColor(for job: HeartBitJob) -> Color {
    if job.executionMode == .cron { return .secondary }
    if job.isRunning { return .yellow }
    if job.lastRunStatus == .delayed { return .orange }
    if job.lastRunStatus == .success { return .green }
    if job.lastRunStatus == .failed { return .red }
    return .secondary
}

func formatSidebarDate(_ date: Date) -> String {
    if !Calendar.current.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    } else {
        return date.formatted(date: .omitted, time: .shortened)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("AppIcon")
                .resizable()
                .frame(width: 100, height: 100)
                .cornerRadius(20)
            
            Text("HeartBit v1.4.1")
                .font(.largeTitle).bold()
            
            Text("HeartBit is a minimal, robust personal task runner for macOS that lives quietly in your menu bar. Built with native Swift and modern SwiftUI, it allows you to schedule scripts, apps, and shell commands just like cron, but with an elegant native Mac interface.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            
            Spacer().frame(height: 40)
            
            Text("(c) 2026, Ivan Diuldia")
                .fontWeight(.medium)
            Text("ivan@diuldia.com")
                .foregroundColor(.blue)
        }
        .padding(40)
        .navigationTitle("About")
    }
}

struct GlobalSettingsView: View {
    @Environment(JobManager.self) private var jobManager
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        Form {
            Section {
                let isEnabledBinding = Binding(
                    get: { !jobManager.isExecutionPaused },
                    set: { jobManager.isExecutionPaused = !$0 }
                )
                
                HStack {
                    Toggle("", isOn: isEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                    if !jobManager.isExecutionPaused {
                        Text("ON").bold()
                    } else {
                        Text("PAUSED").bold()
                    }
                }
            }
            .padding(.bottom, 16)
            
            Section {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() } 
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                
                Toggle("Show app in Dock", isOn: Bindable(jobManager).showInDock)
                
                Button("Request Camera Access") {
                    jobManager.requestCameraAccessFromApp()
                }
            } header: { Text("System Features") }
            .padding(.bottom, 16)

            Section {
                LabeledContent("Default Period (minutes)") {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            value: Bindable(jobManager).defaultPeriodMinutes,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        Stepper(
                            "",
                            value: Bindable(jobManager).defaultPeriodMinutes,
                            in: 1...1440
                        )
                        .labelsHidden()
                    }
                }
                Text("Used for default scheduling slots when creating a new job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Scheduling") }
            .padding(.bottom, 16)
            
            Section {
                Toggle("Log background activity", isOn: Bindable(jobManager).logActivity)
                
                HStack {
                    Text("Retention Policy:")
                    Picker("", selection: Bindable(jobManager).logRetentionDays) {
                        Text("Keep Forever").tag(0)
                        Text("7 Days").tag(7)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                    }
                    .labelsHidden()
                    .disabled(!jobManager.logActivity)
                }
                
                HStack {
                    Button("View Log File") {
                        NSWorkspace.shared.open(jobManager.logURL)
                    }
                    Button("Clear Logs", role: .destructive) {
                        jobManager.clearLogs()
                    }
                }
            } header: { Text("Activity Logging") }
        }
        .padding()
        .navigationTitle("Global Settings")
    }
}

struct CronJobsView: View {
    @Environment(JobManager.self) private var jobManager
    @Binding var selection: SettingsSelection?
    @State private var deletingJob: HeartBitJob?
    @State private var pendingImportData: Data?
    @State private var showImportChoice = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        exportJobsToFile()
                    } label: {
                        Label("Export Jobs…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        pickImportFile()
                    } label: {
                        Label("Import Jobs…", systemImage: "square.and.arrow.down")
                    }
                }
            }

            let sortedJobs = jobManager.jobs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            ForEach(sortedJobs) { job in
                HStack(spacing: 12) {
                    Image(systemName: job.executionMode == .cron ? "circle.dotted" : "heart")
                        .foregroundStyle(job.executionMode == .cron ? .secondary : .primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            selection = .job(job.id)
                        } label: {
                            Text(job.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Text(job.executionMode == .cron ? cronText(for: job) : runEveryText(for: job))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: {
                            if let idx = jobManager.jobs.firstIndex(where: { $0.id == job.id }) {
                                return jobManager.jobs[idx].isEnabled
                            }
                            return false
                        },
                        set: { value in
                            if let idx = jobManager.jobs.firstIndex(where: { $0.id == job.id }) {
                                jobManager.jobs[idx].isEnabled = value
                                jobManager.saveJobs()
                                jobManager.syncCronJobsNow()
                            }
                        })
                    )
                    .labelsHidden()
                    Button(role: .destructive) {
                        deletingJob = job
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            Section {
                Button {
                    selection = .cronTab
                } label: {
                    Label("Crontab", systemImage: "terminal")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("Crono")
        .confirmationDialog(
            "Import jobs",
            isPresented: $showImportChoice,
            titleVisibility: .visible
        ) {
            Button("Replace all jobs", role: .destructive) {
                performImport(replacingExisting: true)
            }
            Button("Add imported jobs") {
                performImport(replacingExisting: false)
            }
            Button("Cancel", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("Choose whether to replace your current job list or append imported jobs (new IDs are assigned when appending).")
        }
        .alert("HeartBit", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "Delete this job?",
            isPresented: Binding(
                get: { deletingJob != nil },
                set: { if !$0 { deletingJob = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let job = deletingJob {
                    jobManager.deleteJob(id: job.id)
                }
                deletingJob = nil
            }
            Button("Cancel", role: .cancel) {
                deletingJob = nil
            }
        } message: {
            if let job = deletingJob {
                Text("This will remove \"\(job.name)\".")
            }
        }
    }

    private func exportJobsToFile() {
        let data: Data
        do {
            data = try jobManager.exportJobsFileData()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
            return
        }
        let savePanel = NSSavePanel()
        savePanel.title = "Export HeartBit Jobs"
        savePanel.nameFieldStringValue = "HeartBit-jobs.json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func pickImportFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import HeartBit Jobs"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try JobManager.decodeJobsForImport(from: data)
            pendingImportData = data
            showImportChoice = true
        } catch {
            alertMessage = "Could not read or decode this file: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func performImport(replacingExisting: Bool) {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try jobManager.importJobs(from: data, replacingExisting: replacingExisting)
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func cronText(for job: HeartBitJob) -> String {
        if !job.customCronExpression.isEmpty {
            return job.customCronExpression
        }
        return JobManager.cronExpression(from: job.scheduleInterval, startDate: job.startDate)
    }

    private func runEveryText(for job: HeartBitJob) -> String {
        if job.scheduleInterval == .custom, !job.customCronExpression.isEmpty {
            return "Custom: \(job.customCronExpression)"
        }
        if job.scheduleInterval == .defaultPeriod {
            return "Every \(jobManager.defaultPeriodMinutes) minutes (Default period)"
        }
        return job.scheduleInterval.rawValue
    }
}

struct CronTabView: View {
    @State private var crontabText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current crontab")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    crontabText = CrontabManager.shared.readRawCrontab()
                }
            }
            TextEditor(text: .constant(crontabText.isEmpty ? "# No crontab entries" : crontabText))
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.3))
        }
        .padding()
        .navigationTitle("CronTab")
        .onAppear {
            crontabText = CrontabManager.shared.readRawCrontab()
        }
    }
}

struct JobDetailView: View {
    @Environment(JobManager.self) private var jobManager
    let jobId: UUID
    @Binding var selection: SettingsSelection?
    @State private var showingDeleteAlert = false
    @State private var showSwitchToHeartBitWarning = false
    @State private var pendingModeAfterWarning: JobExecutionMode?
    
    var jobIndex: Int? { jobManager.jobs.firstIndex(where: { $0.id == jobId }) }
    
    var body: some View {
        Group {
            if let idx = jobIndex {
                let startDateBinding = Binding(
                    get: { jobManager.jobs[idx].startDate },
                    set: { newDate in
                        let adjusted = JobManager.rollStartDateForwardIfTodayAlreadyPassed(newDate)
                        jobManager.jobs[idx].startDate = adjusted
                        let interval = jobManager.jobs[idx].scheduleInterval
                        let mode = jobManager.jobs[idx].executionMode
                        if mode == .heartbit && interval != .custom {
                            jobManager.jobs[idx].customCronExpression = JobManager.cronExpression(from: interval, startDate: adjusted)
                        } else if mode == .cron || interval == .custom {
                            let current = jobManager.jobs[idx].customCronExpression
                            let base = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? JobManager.cronExpression(from: .hour, startDate: adjusted)
                                : current
                            jobManager.jobs[idx].customCronExpression = JobManager.mergeStartDateIntoCronExpression(
                                base,
                                startDate: adjusted,
                                updateCalendarFields: interval == .once
                            )
                        }
                        jobManager.saveJobs()
                        jobManager.rescheduleHeartBitJob(at: idx)
                        jobManager.syncCronJobsNow()
                    }
                )
                let scheduleIntervalBinding = Binding(
                    get: { jobManager.jobs[idx].scheduleInterval },
                    set: { applySchedulePreset(idx: idx, interval: $0) }
                )
                
                let modeBinding = Binding(
                    get: { jobManager.jobs[idx].executionMode },
                    set: {
                        let currentMode = jobManager.jobs[idx].executionMode
                        if currentMode == .cron,
                           $0 == .heartbit,
                           jobManager.jobs[idx].isImportedFromExternalCron,
                           !jobManager.jobs[idx].didConfirmHeartBitSwitch {
                            pendingModeAfterWarning = $0
                            showSwitchToHeartBitWarning = true
                            return
                        }
                        applyModeChange(idx: idx, mode: $0)
                    }
                )
                let cronExpressionBinding = Binding(
                    get: {
                        let current = jobManager.jobs[idx].customCronExpression
                        if !current.isEmpty { return current }
                        return JobManager.cronExpression(from: jobManager.jobs[idx].scheduleInterval, startDate: jobManager.jobs[idx].startDate)
                    },
                    set: {
                        jobManager.jobs[idx].customCronExpression = $0
                        jobManager.jobs[idx].scheduleInterval = .custom
                        jobManager.saveJobs()
                        jobManager.rescheduleHeartBitJob(at: idx)
                        DispatchQueue.main.async {
                            jobManager.syncCronJobsNow()
                        }
                    }
                )
                
                ScrollView {
                    Form {
                        Section {
                            TextField("Name", text: Bindable(jobManager).jobs[idx].name)
                            HStack {
                                TextField("Command / Path", text: Bindable(jobManager).jobs[idx].command)
                                Button("Choose App...") { selectApp(idx: idx) }
                            }
                            Text("Security: this command runs through /bin/zsh with your macOS user permissions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 16)
                        
                        Section {
                            Picker("Engine:", selection: modeBinding) {
                                ForEach(JobExecutionMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(jobManager.jobs[idx].scheduleInterval == .once)

                            if jobManager.jobs[idx].scheduleInterval == .once {
                                VStack(alignment: .leading) {
                                    HStack {
                                        DatePicker("Start:", selection: startDateBinding, displayedComponents: [.date])
                                            .datePickerStyle(.graphical)
                                            .frame(maxWidth: 300)
                                        
                                        DatePicker("Time", selection: startDateBinding, displayedComponents: [.hourAndMinute])
                                            .datePickerStyle(.compact)
                                            .labelsHidden()
                                            .padding(.leading)
                                    }
                                }
                            } else {
                                DatePicker("Time (anchor)", selection: startDateBinding, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.compact)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                if jobManager.jobs[idx].executionMode == .heartbit {
                                    LabeledContent("Run every:") {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Picker("", selection: scheduleIntervalBinding) {
                                                ForEach(ScheduleInterval.allCases) { interval in
                                                    Text(interval.rawValue).tag(interval)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(maxWidth: 280, alignment: .leading)
                                            if jobManager.jobs[idx].scheduleInterval == .custom {
                                                TextField("", text: cronExpressionBinding)
                                                    .font(.system(.body, design: .monospaced))
                                                    .textFieldStyle(.roundedBorder)
                                                    .frame(width: 280, alignment: .leading)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                    }
                                } else {
                                    LabeledContent("Run every (cron):") {
                                        TextField("", text: cronExpressionBinding)
                                            .font(.system(.body, design: .monospaced))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 280, alignment: .leading)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                if jobManager.jobs[idx].scheduleInterval == .once && jobManager.jobs[idx].executionMode == .heartbit {
                                    Text("Runs once, then stops.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if jobManager.jobs[idx].executionMode == .heartbit {
                                Picker("Missed Run Policy:", selection: Bindable(jobManager).jobs[idx].missedRunPolicy) {
                                    ForEach(MissedRunPolicy.allCases) { policy in Text(policy.rawValue).tag(policy) }
                                }
                                Toggle("Online only", isOn: Bindable(jobManager).jobs[idx].isOnlineOnly)
                                if jobManager.jobs[idx].isOnlineOnly {
                                    Text("When offline, scheduled runs are delayed and retried every Default Period.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                HStack {
                                    Text("Missed Run Policy:")
                                    Spacer()
                                    Text("Disabled in Cron mode")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let nextRun = jobManager.jobs[idx].nextExpectedRunDate {
                                if nextRun < Date() {
                                    Text("Scheduled Run: \(nextRun.formatted())")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Next Scheduled Run: \(nextRun.formatted())")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let retryAfter = jobManager.jobs[idx].onlineRetryAfterDate {
                                Text("Offline Retry After: \(retryAfter.formatted())")
                                    .foregroundStyle(.secondary)
                            }
                            if jobManager.jobs[idx].lastRunStatus == .delayed {
                                Text("Last scheduled run was delayed while offline.")
                                    .foregroundStyle(.secondary)
                            }
                            if let lastRun = jobManager.jobs[idx].lastRunDate {
                                Text("Last Run: \(lastRun.formatted())")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 16)
                        
                        let hasOutput = !jobManager.jobs[idx].latestOutput.isEmpty
                        let isRunning = jobManager.jobs[idx].isRunning
                        
                        if hasOutput || isRunning {
                            Section {
                                if isRunning {
                                    HStack {
                                        ProgressView().controlSize(.small).padding(.trailing, 8)
                                        Text("Running...")
                                    }
                                }
                                TextEditor(text: .constant(jobManager.jobs[idx].latestOutput))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 75, maxHeight: 150)
                                    .border(Color.gray.opacity(0.3))
                            }
                            .padding(.bottom, 24)
                        }
                        
                        Divider()
                        HStack {
                            Toggle("Enable Job", isOn: Bindable(jobManager).jobs[idx].isEnabled)
                                .toggleStyle(.switch)
                            Spacer()
                            
                            Button("Run Job") { jobManager.enqueueJob(id: jobId, isDryRun: false) }
                                .disabled(isRunning || jobManager.jobs[idx].command.isEmpty || jobManager.isExecutionPaused)
                                .padding(.trailing)

                            Button("Dry-Run Now") { jobManager.enqueueJob(id: jobId, isDryRun: true) }
                                .disabled(isRunning || jobManager.jobs[idx].command.isEmpty || jobManager.isExecutionPaused)
                                .padding(.trailing)
                                
                            Button("Delete Job", role: .destructive) {
                                showingDeleteAlert = true
                            }
                            .confirmationDialog("Are you sure you want to delete this job?", isPresented: $showingDeleteAlert, titleVisibility: .visible) {
                                Button("Delete", role: .destructive) {
                                    selection = .globalSettings
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        jobManager.deleteJob(id: jobId)
                                    }
                                }
                                Button("Cancel", role: .cancel) { }
                            }
                        }
                        .padding(.top, 16)
                    }
                    .padding()
                }
                .navigationTitle(jobManager.jobs[idx].name)
                .onChange(of: jobManager.jobs[idx]) { _, _ in
                    jobManager.saveJobs()
                    if jobManager.jobs[idx].executionMode == .cron {
                        jobManager.syncCronJobsNow()
                    }
                }
                .confirmationDialog(
                    "Switch imported Cron job to HeartBit mode?",
                    isPresented: $showSwitchToHeartBitWarning,
                    titleVisibility: .visible
                ) {
                    Button("Switch to HeartBit", role: .destructive) {
                        guard let mode = pendingModeAfterWarning else { return }
                        jobManager.jobs[idx].didConfirmHeartBitSwitch = true
                        applyModeChange(idx: idx, mode: mode)
                        pendingModeAfterWarning = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingModeAfterWarning = nil
                    }
                } message: {
                    Text("This job was imported from system crontab. Switching to HeartBit changes scheduling semantics and can alter behavior.")
                }
            } else {
                Text("Job not found")
            }
        }
    }
    
    private func applySchedulePreset(idx: Int, interval: ScheduleInterval) {
        if interval == .once {
            jobManager.jobs[idx].scheduleInterval = .once
            jobManager.jobs[idx].customCronExpression = ""
        } else {
            jobManager.jobs[idx].scheduleInterval = interval
            if interval != .custom {
                jobManager.jobs[idx].customCronExpression = JobManager.cronExpression(from: interval, startDate: jobManager.jobs[idx].startDate)
            } else if jobManager.jobs[idx].customCronExpression.isEmpty {
                jobManager.jobs[idx].customCronExpression = JobManager.cronExpression(from: .hour, startDate: jobManager.jobs[idx].startDate)
            }
        }
        jobManager.rescheduleHeartBitJob(at: idx)
        DispatchQueue.main.async {
            jobManager.syncCronJobsNow()
        }
    }

    private func selectApp(idx: Int) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        
        if panel.runModal() == .OK, let url = panel.url {
            let executablePath = url.path
            jobManager.jobs[idx].command = "open -a \"\(executablePath)\""
            jobManager.saveJobs()
            jobManager.syncCronJobsNow()
        }
    }

    private func applyModeChange(idx: Int, mode: JobExecutionMode) {
        jobManager.jobs[idx].executionMode = mode
        if mode == .cron {
            let interval = jobManager.jobs[idx].scheduleInterval
            if interval == .defaultPeriod {
                let minutes = jobManager.defaultPeriodMinutes
                jobManager.jobs[idx].customCronExpression = JobManager.cronExpressionForDefaultPeriod(
                    minutes: minutes,
                    startDate: jobManager.jobs[idx].startDate
                )
                jobManager.jobs[idx].scheduleInterval = .custom
            } else if interval == .custom {
                let existing = jobManager.jobs[idx].customCronExpression
                let baseExpression = existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? JobManager.cronExpression(from: .hour, startDate: jobManager.jobs[idx].startDate)
                    : existing
                jobManager.jobs[idx].customCronExpression = JobManager.mergeStartDateIntoCronExpression(
                    baseExpression,
                    startDate: jobManager.jobs[idx].startDate,
                    updateCalendarFields: false
                )
            } else {
                jobManager.jobs[idx].customCronExpression = JobManager.cronExpression(
                    from: interval,
                    startDate: jobManager.jobs[idx].startDate
                )
            }
        }
        jobManager.saveJobs()
        DispatchQueue.main.async {
            jobManager.syncCronJobsNow()
        }
        DispatchQueue.main.async {
            selection = .job(jobId)
        }
    }
}
