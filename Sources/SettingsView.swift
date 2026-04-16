import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

enum SettingsSelection: Hashable {
    case about
    case globalSettings
    case timetable
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
                    NavigationLink(value: SettingsSelection.timetable) {
                        Label("Timetable", systemImage: "calendar")
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
            case .timetable:
                TimetableView { date in addNewJob(at: date) }
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
            comps.minute = ((comps.minute ?? 0) / 5) * 5 + 10 // +5 buffer + up to next 5
            if let nextSlot = cal.date(from: comps) { newJob.startDate = nextSlot }
        }
        jobManager.addJob(newJob)
        selection = .job(newJob.id)
    }
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
            
            Text("HeartBit v1.3.3")
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
            } header: { Text("System Features") }
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

struct TimetableView: View {
    @Environment(JobManager.self) private var jobManager
    let onAddTime: (Date) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today's Agenda")
                    .font(.title2).bold()
                    .padding()
                
                let cal = Calendar.current
                let startOfDay = cal.startOfDay(for: Date())
                
                let todayJobs = jobManager.jobs.filter { job in
                    if let nex = job.nextExpectedRunDate, cal.isDateInToday(nex) { return true }
                    if let last = job.lastRunDate, cal.isDateInToday(last) { return true }
                    return false
                }
                
                ForEach(0..<24) { hour in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text("\(hour):00")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .trailing)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Divider()
                                
                                let slotStart = cal.date(byAdding: .hour, value: hour, to: startOfDay)!
                                let slotEnd = cal.date(byAdding: .hour, value: 1, to: slotStart)!
                                
                                let jobsInSlot = todayJobs.filter { job in
                                    let activeDate = job.nextExpectedRunDate ?? (job.lastRunDate ?? slotStart)
                                    return activeDate >= slotStart && activeDate < slotEnd 
                                }
                                
                                if !jobsInSlot.isEmpty {
                                    ForEach(jobsInSlot) { job in
                                        HStack {
                                            let hasNext = job.nextExpectedRunDate != nil && job.isEnabled
                                            Circle()
                                                .fill(statusColor(status: job.lastRunStatus, hasNext: hasNext))
                                                .frame(width: 8, height: 8)
                                            
                                            let timeDisplay = (job.nextExpectedRunDate ?? job.lastRunDate)?.formatted(date: .omitted, time: .shortened) ?? ""
                                            Text(timeDisplay).font(.caption).bold()
                                            Text(job.name).font(.subheadline)
                                            Spacer()
                                            
                                            if job.scheduleInterval != .once {
                                                Image(systemName: "arrow.rectanglepath").font(.caption2).foregroundColor(.secondary)
                                            }
                                            Text(statusText(job: job)).font(.caption2).foregroundColor(.secondary)
                                        }
                                        .padding(6)
                                        .background(statusColor(status: job.lastRunStatus, hasNext: job.nextExpectedRunDate != nil && job.isEnabled).opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                } else {
                                    Color.clear
                                        .frame(height: 25)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onAddTime(slotStart) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle("Timetable")
    }
    
    private func statusColor(status: JobStatus, hasNext: Bool) -> Color {
        if hasNext && status == .idle { return .blue }
        switch status {
        case .idle: return .gray
        case .running: return .yellow
        case .success: return .green
        case .failed: return .red
        }
    }
    
    private func statusText(job: HeartBitJob) -> String {
        if !job.isEnabled { return "Disabled" }
        if job.isRunning { return "Running" }
        if job.nextExpectedRunDate != nil && job.lastRunStatus == .idle { return "Pending" }
        switch job.lastRunStatus {
        case .idle: return "Pending"
        case .running: return "Running"
        case .success: return "Done"
        case .failed: return "Error"
        }
    }
}

struct JobDetailView: View {
    @Environment(JobManager.self) private var jobManager
    let jobId: UUID
    @Binding var selection: SettingsSelection?
    @State private var showingDeleteAlert = false
    
    var jobIndex: Int? { jobManager.jobs.firstIndex(where: { $0.id == jobId }) }
    
    var body: some View {
        Group {
            if let idx = jobIndex {
                let startDateBinding = Binding(
                    get: { jobManager.jobs[idx].startDate },
                    set: { 
                        jobManager.jobs[idx].startDate = $0
                        jobManager.jobs[idx].nextExpectedRunDate = $0
                        jobManager.saveJobs()
                    }
                )
                
                let intervalBinding = Binding(
                    get: { jobManager.jobs[idx].scheduleInterval },
                    set: { 
                        jobManager.jobs[idx].scheduleInterval = $0
                        jobManager.jobs[idx].nextExpectedRunDate = nil
                        jobManager.saveJobs()
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
                        }
                        .padding(.bottom, 16)
                        
                        Section {
                            VStack(alignment: .leading) {
                                HStack {
                                    DatePicker("Start Date", selection: startDateBinding, displayedComponents: [.date])
                                        .datePickerStyle(.graphical)
                                        .frame(maxWidth: 300)
                                    
                                    DatePicker("Time", selection: startDateBinding, displayedComponents: [.hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .padding(.leading)
                                }
                            }
                            
                            Picker("Run every:", selection: intervalBinding) {
                                ForEach(ScheduleInterval.allCases) { interval in Text(interval.rawValue).tag(interval) }
                            }
                            Picker("Missed Run Policy:", selection: Bindable(jobManager).jobs[idx].missedRunPolicy) {
                                ForEach(MissedRunPolicy.allCases) { policy in Text(policy.rawValue).tag(policy) }
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
                            
                            Button("Dry-Run Now") { jobManager.enqueueJob(id: jobId, isDryRun: true) }
                                .disabled(isRunning || jobManager.jobs[idx].command.isEmpty || jobManager.isExecutionPaused)
                                .padding(.trailing)
                                
                            Button("Delete Job", role: .destructive) {
                                if jobManager.jobs[idx].command.isEmpty {
                                    selection = .globalSettings
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        jobManager.deleteJob(id: jobId)
                                    }
                                } else {
                                    showingDeleteAlert = true
                                }
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
                }
            } else {
                Text("Job not found")
            }
        }
    }
    
    private func selectApp(idx: Int) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application] 
        panel.allowedFileTypes = ["app"]
        
        if panel.runModal() == .OK, let url = panel.url {
            let executablePath = url.path
            jobManager.jobs[idx].command = "open -a \"\(executablePath)\""
            jobManager.saveJobs()
        }
    }
}
