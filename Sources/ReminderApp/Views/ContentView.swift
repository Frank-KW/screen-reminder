import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var timeBlockSettings: TimeBlockSettings
    @EnvironmentObject private var worldClockStore: WorldClockStore
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var eventStore: EventStore
    @State private var showsWorldClocks = false
    @State private var showsEvents = false

    let onExport: () -> Void
    let onRestore: () -> Void

    @State private var title = ""
    @State private var selectedTimeBlock: TimeBlock = .morningWorkBlock
    @State private var startTime = TimeUtils.date(from: 9 * 3_600)
    @State private var endTime = TimeUtils.date(from: 12 * 3_600)
    @State private var hasAppliedInitialTimeBlock = false
    @State private var repeatDays: Set<Int> = []
    @State private var selectedImageURL: URL?
    @State private var selectedImagePreview: NSImage?
    @State private var retainedImageFilename: String?
    @State private var editingTaskID: UUID?
    @State private var showReminder = false
    @State private var window: NSWindow?
    @State private var validationMessage: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            if showReminder {
                ReminderView(store: store) {
                    showReminder = false
                }
                .transition(.opacity)
            } else {
                dashboard
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .animation(.easeInOut(duration: 0.25), value: showReminder)
        .background(WindowAccessor { window in
            guard self.window !== window else { return }
            self.window = window
            self.window?.titleVisibility = .hidden
            self.window?.titlebarAppearsTransparent = true
        })
        .onChange(of: showReminder) { isShowingReminder in
            updateFullScreen(isShowingReminder)
        }
        .onAppear {
            guard !hasAppliedInitialTimeBlock else { return }
            hasAppliedInitialTimeBlock = true
            applyPreset(for: selectedTimeBlock)
        }
        .onExitCommand {
            if showReminder {
                showReminder = false
            }
        }
        .sheet(isPresented: $showsWorldClocks) {
            WorldClocksManagerView()
                .environmentObject(worldClockStore)
        }
        .sheet(isPresented: $showsEvents) {
            EventsManagerView(onExport: onExport, onRestore: onRestore)
                .environmentObject(eventStore)
        }
        .alert(
            eventStore.inAppAlerts.first?.title ?? "Event",
            isPresented: Binding(
                get: { !eventStore.inAppAlerts.isEmpty },
                set: { if !$0 { eventStore.dismissInAppAlert() } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(eventStore.inAppAlerts.first?.body ?? "")
        }
    }

    private var dashboard: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 22) {
                    createTaskPanel
                        .frame(width: 350)

                    taskListPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 32)
                .padding(.top, 30)
                .padding(.bottom, 30)
            }
        }
    }

    private var createTaskPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(editingTaskID == nil ? "New reminder" : "Edit reminder")
                        .font(.title2.bold())
                    Text(editingTaskID == nil
                         ? "A matching task appears automatically during its time window."
                         : "Update the task, schedule, repeat days, or photo.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if editingTaskID != nil {
                    Button("Cancel", action: cancelEditing)
                        .buttonStyle(.borderless)
                        .help("Cancel editing this reminder")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("TASK")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                TextField("What needs your attention?", text: $title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isTitleFocused ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isTitleFocused ? 2 : 1)
                    }
                    .focused($isTitleFocused)
                    .onSubmit(submitTask)
            }

            timeBlockPicker

            timeRangeEditor

            Divider()

            RepeatDaysPicker(selectedDays: $repeatDays)

            Divider()

            taskPhotoField

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundColor(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: submitTask) {
                HStack {
                    Image(systemName: editingTaskID == nil ? "plus" : "checkmark")
                    Text(editingTaskID == nil ? "Add Reminder" : "Save Changes")
                        .fontWeight(.semibold)
                    Spacer()
                    Text("⌘↩")
                        .font(.caption.monospaced())
                        .foregroundColor(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(24)
        .reminderPanel()
    }

    private var taskListPanel: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let activeTask = store.activeTask(at: context.date)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your schedule")
                            .font(.title2.bold())
                        Text(taskCountText)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let activeTask {
                        Label(activeTask.title, systemImage: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.10), in: Capsule())
                            .accessibilityLabel("Active now: \(activeTask.title)")
                    }

                    Button {
                        showsEvents = true
                    } label: {
                        Label(eventsButtonTitle(at: context.date), systemImage: "calendar")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .help("Add events with a date, time and alerts (Shift-Command-E)")

                    Button {
                        showsWorldClocks = true
                    } label: {
                        Label(worldClockButtonTitle, systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .help("Add, edit, or remove city clocks (Shift-Command-K)")

                    Button {
                        showReminder = true
                    } label: {
                        Label("Open Display", systemImage: "arrow.up.left.and.arrow.down.right")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Open the full-screen reminder (Shift-Command-R)")
                }

                if let warning = store.storageWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.callout)
                        .foregroundColor(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                if store.tasks.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.tasks) { task in
                                TaskRow(
                                    task: task,
                                    image: store.image(for: task),
                                    isActive: task.id == activeTask?.id,
                                    isEditing: task.id == editingTaskID,
                                    onEdit: { beginEditing(task) },
                                    onDelete: { deleteTask(task) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(24)
            .reminderPanel()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 66, height: 66)

            Text("Your schedule is clear")
                .font(.headline)
            Text("Add a reminder and it will appear here in chronological order.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

    private func eventsButtonTitle(at now: Date) -> String {
        let count = eventStore.upcoming(at: now).count
        return count == 0 ? "Events" : "Events (\(count))"
    }

    private var worldClockButtonTitle: String {
        worldClockStore.clocks.isEmpty ? "World Clocks" : "World Clocks (\(worldClockStore.clocks.count))"
    }

    private var taskCountText: String {
        switch store.tasks.count {
        case 0: return "No reminders yet"
        case 1: return "1 reminder"
        default: return "\(store.tasks.count) reminders"
        }
    }

    private var selectedTimeRange: TimeBlockRange {
        timeBlockSettings.range(for: selectedTimeBlock)
    }

    private var currentTimeRange: TimeBlockRange {
        TimeBlockRange(
            startSeconds: TimeUtils.secondsSinceMidnight(for: startTime),
            endSeconds: TimeUtils.secondsSinceMidnight(for: endTime)
        )
    }

    private var isUsingSelectedPreset: Bool {
        currentTimeRange == selectedTimeRange
    }

    private var timeBlockSelection: Binding<TimeBlock> {
        Binding(
            get: { selectedTimeBlock },
            set: { block in
                selectedTimeBlock = block
                applyPreset(for: block)
            }
        )
    }

    private var timeBlockPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIME BLOCK")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Picker("Time block", selection: timeBlockSelection) {
                ForEach(TimeBlock.allCases) { block in
                    Text("\(block.displayName) — \(timeBlockSettings.range(for: block).timeRangeText)")
                        .tag(block)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Time block")

            HStack(spacing: 8) {
                Label("Preset: \(selectedTimeRange.timeRangeText)", systemImage: selectedTimeBlock.symbolName)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !isUsingSelectedPreset {
                    Button("Use Preset") {
                        applyPreset(for: selectedTimeBlock)
                    }
                    .buttonStyle(.borderless)
                    .help("Restore the configured \(selectedTimeBlock.displayName) times")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var timeRangeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                timeInputCard(
                    title: "START",
                    systemImage: "play.fill",
                    selection: $startTime
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)

                timeInputCard(
                    title: "END",
                    systemImage: "stop.fill",
                    selection: $endTime
                )
            }

            HStack(spacing: 6) {
                Label(timeRangeSummary, systemImage: timeRangeSummaryIcon)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text(isUsingSelectedPreset ? "Preset" : "Adjusted")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(isUsingSelectedPreset ? .green : .orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (isUsingSelectedPreset ? Color.green : Color.orange).opacity(0.10),
                        in: Capsule()
                    )
            }

            Text("Edit preset defaults in Settings (⌘,).")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func timeInputCard(
        title: String,
        systemImage: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundColor(.secondary)

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .controlSize(.large)
                .accessibilityLabel(title.capitalized)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.primary.opacity(0.08))
        }
    }

    private var timeRangeSummary: String {
        let start = currentTimeRange.startSeconds
        let end = currentTimeRange.endSeconds
        guard start != end else { return "All day · 24 hr" }

        let duration = end > start
            ? end - start
            : TimeUtils.secondsPerDay - start + end
        let prefix = end < start ? "Overnight" : "Duration"
        return "\(prefix) · \(durationText(for: duration))"
    }

    private var timeRangeSummaryIcon: String {
        if currentTimeRange.startSeconds == currentTimeRange.endSeconds {
            return "sun.max.fill"
        }
        return currentTimeRange.endSeconds < currentTimeRange.startSeconds
            ? "moon.stars.fill"
            : "clock.fill"
    }

    private func durationText(for seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if minutes == 0 {
            return "\(hours) hr"
        }
        if hours == 0 {
            return "\(minutes) min"
        }
        return "\(hours) hr \(minutes) min"
    }

    private var taskPhotoField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PHOTO")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("OPTIONAL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }

            if let preview = selectedImagePreview {
                HStack(spacing: 11) {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedImageURL?.deletingPathExtension().lastPathComponent ?? "Current photo")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text("Shown full screen when active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 4)

                    Button("Replace", action: choosePhoto)
                        .buttonStyle(.borderless)
                    Button(action: removeSelectedPhoto) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove selected photo")
                    .accessibilityLabel("Remove selected photo")
                }
                .padding(9)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            } else {
                Button(action: choosePhoto) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose a photo")
                                .font(.callout.weight(.semibold))
                            Text("It becomes the active display background")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(10)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.primary.opacity(0.08))
                }
            }
        }
    }

    private func submitTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            withAnimation {
                validationMessage = "Enter a task before saving the reminder."
            }
            isTitleFocused = true
            return
        }

        var importedImageFilename: String?
        do {
            importedImageFilename = try selectedImageURL.map { try store.importImage(from: $0) }
        } catch {
            withAnimation {
                validationMessage = error.localizedDescription
            }
            return
        }

        let imageFilename = importedImageFilename ?? retainedImageFilename
        let didSave: Bool
        if let editingTask {
            didSave = store.updateTask(
                editingTask,
                title: trimmedTitle,
                start: startTime,
                end: endTime,
                repeatDays: repeatDays,
                imageFilename: imageFilename,
                timeBlock: selectedTimeBlock
            )
        } else {
            didSave = store.addTask(
                title: trimmedTitle,
                start: startTime,
                end: endTime,
                repeatDays: repeatDays,
                imageFilename: imageFilename,
                timeBlock: selectedTimeBlock
            )
        }

        guard didSave else {
            if let importedImageFilename {
                store.discardImage(named: importedImageFilename)
            }
            withAnimation {
                validationMessage = store.storageWarning ?? "The reminder could not be saved."
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            resetForm(resetTimes: editingTaskID != nil)
        }
        isTitleFocused = true
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Reminder Photo"
        panel.message = "Choose an image to show while this reminder is active."
        panel.prompt = "Choose Photo"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            withAnimation {
                validationMessage = "The selected photo could not be read."
            }
            return
        }

        selectedImageURL = url
        selectedImagePreview = image
        validationMessage = nil
    }

    private func removeSelectedPhoto() {
        selectedImageURL = nil
        selectedImagePreview = nil
        retainedImageFilename = nil
    }

    private var editingTask: TaskItem? {
        guard let editingTaskID else { return nil }
        return store.tasks.first { $0.id == editingTaskID }
    }

    private func beginEditing(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            editingTaskID = task.id
            title = task.title
            selectedTimeBlock = task.timeBlock
                ?? timeBlockSettings.matchingBlock(
                    startSeconds: task.startSeconds,
                    endSeconds: task.endSeconds
                )
                ?? .morningWorkBlock
            startTime = TimeUtils.date(from: task.startSeconds)
            endTime = TimeUtils.date(from: task.endSeconds)
            repeatDays = Set(task.repeatDays)
            selectedImageURL = nil
            selectedImagePreview = store.image(for: task)
            retainedImageFilename = task.imageFilename
            validationMessage = nil
        }
        isTitleFocused = true
    }

    private func cancelEditing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            resetForm(resetTimes: true)
        }
        isTitleFocused = true
    }

    private func resetForm(resetTimes: Bool) {
        editingTaskID = nil
        title = ""
        repeatDays = []
        selectedImageURL = nil
        selectedImagePreview = nil
        retainedImageFilename = nil
        validationMessage = nil
        if resetTimes {
            selectedTimeBlock = .morningWorkBlock
            applyPreset(for: .morningWorkBlock)
        }
    }

    private func applyPreset(for block: TimeBlock) {
        let range = timeBlockSettings.range(for: block)
        startTime = TimeUtils.date(from: range.startSeconds, on: startTime)
        endTime = TimeUtils.date(from: range.endSeconds, on: endTime)
    }

    private func deleteTask(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if editingTaskID == task.id {
                resetForm(resetTimes: true)
            }
            store.deleteTask(task)
        }
    }

    private func updateFullScreen(_ shouldEnterFullScreen: Bool) {
        guard let window else { return }
        if shouldEnterFullScreen, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else if !shouldEnterFullScreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let image: NSImage?
    let isActive: Bool
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var confirmsDeletion = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.green.opacity(0.14) : Color.accentColor.opacity(0.09))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color.black.opacity(isActive ? 0.02 : 0.08))
                } else {
                    Image(systemName: isActive ? "bolt.fill" : "clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(isActive ? .green : .accentColor)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if image != nil, isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.green, lineWidth: 2)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if isActive {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.10), in: Capsule())
                    }
                }

                HStack(spacing: 12) {
                    Label(task.scheduleTimeText, systemImage: "clock")
                    Label(task.repeatSummary, systemImage: "repeat")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundColor(isEditing ? .accentColor : .secondary)
            .help("Edit \(task.title)")
            .accessibilityLabel("Edit \(task.title)")

            Button {
                confirmsDeletion = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Delete \(task.title)")
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isEditing
                ? Color.accentColor.opacity(0.09)
                : (isActive ? Color.green.opacity(0.055) : Color.primary.opacity(0.035)),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.38), lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if isActive {
                Capsule()
                    .fill(Color.green)
                    .frame(width: 3)
                    .padding(.vertical, 10)
            }
        }
        .alert("Delete this reminder?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("\"\(task.title)\" will be removed from your schedule.")
        }
    }
}

private struct ReminderPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
    }
}

private extension View {
    func reminderPanel() -> some View {
        modifier(ReminderPanelModifier())
    }
}
