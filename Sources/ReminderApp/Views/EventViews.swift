import SwiftUI

/// The Events window: a list of events on the left, the editor on the right.
struct EventsManagerView: View {
    @EnvironmentObject private var eventStore: EventStore
    @Environment(\.dismiss) private var dismiss

    let onExport: () -> Void
    let onRestore: () -> Void

    @State private var editingID: UUID?
    @State private var title = ""
    @State private var day = Date()
    @State private var startTime = EventsManagerView.nextHour()
    @State private var endTime = EventsManagerView.nextHour().addingTimeInterval(3_600)
    @State private var alerts: [Int] = [10]
    @State private var notes = ""
    @State private var customCount = 1
    @State private var customUnit: EventFormat.Unit = .hours
    @State private var showsCustom = false
    @State private var message: String?
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Events").font(.title2.bold())
                    Text("One-off events on a date, with alerts before they start.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Export Backup…", action: onExport)
                    .help("Save all your data to a file (Shift-Command-B)")
                Button("Restore…", action: onRestore)
                    .help("Bring back data from a backup file")
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            HStack(alignment: .top, spacing: 0) {
                eventList
                    .frame(width: 300)
                Divider()
                ScrollView {
                    editor.padding(20)
                }
            }
        }
        .frame(width: 940, height: 660)
    }

    // MARK: List

    private var eventList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let upcoming = eventStore.upcoming(at: context.date)
            let past = eventStore.past(at: context.date)
            List(selection: Binding(get: { editingID }, set: { id in
                if let id, let event = eventStore.event(withID: id) { beginEditing(event) }
            })) {
                Section("Upcoming") {
                    if upcoming.isEmpty {
                        Text("No upcoming events").foregroundColor(.secondary)
                    }
                    ForEach(upcoming) { event in
                        EventRow(event: event, isNow: event.isHappening(at: context.date)).tag(event.id)
                    }
                }
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { event in
                            EventRow(event: event, isNow: false).tag(event.id).opacity(0.6)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                Button {
                    resetForm()
                } label: {
                    Label("New Event", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(12)
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(editingID == nil ? "New event" : "Edit event").font(.title3.bold())
                Spacer()
                if let editingID {
                    Button(role: .destructive) {
                        eventStore.delete(editingID)
                        resetForm()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            field("TITLE") {
                TextField("Add title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isTitleFocused)
            }

            HStack(alignment: .top, spacing: 20) {
                field("DATE") {
                    MonthCalendar(selection: $day)
                        .frame(width: 300)
                }

                VStack(alignment: .leading, spacing: 16) {
                    field("STARTS") {
                        DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .controlSize(.large)
                    }
                    field("ENDS") {
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .controlSize(.large)
                    }
                    Label(whenSummary, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    field("NOTIFICATIONS") {
                        alertEditor
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            field("NOTES") {
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
            }

            if let message {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundColor(.red)
            }

            HStack {
                if editingID != nil {
                    Button("Cancel", action: resetForm)
                }
                Spacer()
                Button(action: save) {
                    Label(editingID == nil ? "Add Event" : "Save Changes",
                          systemImage: editingID == nil ? "plus" : "checkmark")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .onAppear { isTitleFocused = true }
    }

    private var alertEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if alerts.isEmpty {
                Text("No notification").foregroundColor(.secondary)
            }
            ForEach(Array(alerts.enumerated()), id: \.offset) { index, minutes in
                HStack {
                    Image(systemName: "bell").foregroundColor(.secondary)
                    Picker("Notification", selection: Binding(
                        get: { minutes },
                        set: { alerts[index] = $0; alerts = EventItem.cleanAlerts(alerts) }
                    )) {
                        ForEach(alertChoices(including: minutes), id: \.self) { value in
                            Text(EventFormat.alertText(value)).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Button {
                        alerts.remove(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this notification")
                    .accessibilityLabel("Remove \(EventFormat.alertText(minutes))")
                }
            }

            if alerts.count < EventItem.maxAlerts {
                HStack(spacing: 12) {
                    Button {
                        addAlert(EventFormat.presetAlertMinutes.first { !alerts.contains($0) } ?? 0)
                    } label: {
                        Label("Add notification", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Button(showsCustom ? "Hide custom" : "Custom…") { showsCustom.toggle() }
                        .buttonStyle(.borderless)
                }
                if showsCustom {
                    HStack {
                        TextField("Amount", value: $customCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Picker("Unit", selection: $customUnit) {
                            ForEach(EventFormat.Unit.allCases) { unit in
                                Text(unit.pluralLabel).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 95)
                        Text("before")
                        Button("Add") {
                            let minutes = customCount * customUnit.rawValue
                            guard customCount >= 0, minutes <= EventItem.maxAlertMinutes else {
                                message = "A notification can be at most 4 weeks before."
                                return
                            }
                            addAlert(minutes)
                            showsCustom = false
                        }
                    }
                }
            } else {
                Text("Up to \(EventItem.maxAlerts) notifications per event.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    // MARK: Logic

    private var startDate: Date { EventFormat.combine(day: day, time: startTime) }
    private var endDate: Date { EventFormat.endDate(start: startDate, endTime: endTime) }

    private var whenSummary: String {
        let preview = EventItem(title: "", startDate: startDate, endDate: endDate)
        return "\(EventFormat.dayText(startDate)) · \(EventFormat.timeRangeText(preview))"
    }

    private func alertChoices(including value: Int) -> [Int] {
        Array(Set(EventFormat.presetAlertMinutes + [value])).sorted()
    }

    private func addAlert(_ minutes: Int) {
        alerts = EventItem.cleanAlerts(alerts + [minutes])
        message = nil
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Enter a title before saving the event."
            isTitleFocused = true
            return
        }
        let didSave: Bool
        if let editingID {
            didSave = eventStore.update(editingID, title: trimmed, start: startDate, end: endDate, alertMinutes: alerts, notes: notes)
        } else {
            didSave = eventStore.add(title: trimmed, start: startDate, end: endDate, alertMinutes: alerts, notes: notes)
        }
        guard didSave else {
            message = eventStore.storageWarning ?? "The event could not be saved."
            return
        }
        resetForm()
    }

    private func beginEditing(_ event: EventItem) {
        editingID = event.id
        title = event.title
        day = event.startDate
        startTime = event.startDate
        endTime = event.endDate
        alerts = event.alertMinutes
        notes = event.notes
        showsCustom = false
        message = nil
    }

    private func resetForm() {
        editingID = nil
        title = ""
        day = Date()
        startTime = Self.nextHour()
        endTime = Self.nextHour().addingTimeInterval(3_600)
        alerts = [10]
        notes = ""
        showsCustom = false
        message = nil
        isTitleFocused = true
    }

    static func nextHour(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return hourStart.addingTimeInterval(3_600)
    }
}

/// A month grid for picking a day. Drawn by hand so it can be big; the system one has a fixed size.
struct MonthCalendar: View {
    @Binding var selection: Date
    @State private var shownMonth = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.bold())
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous month")
                    .accessibilityLabel("Previous month")
                Button("Today") {
                    selection = combineKeepingTime(Date())
                    shownMonth = Date()
                }
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next month")
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            .font(.body.weight(.semibold))

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(height: 22)
                }
                ForEach(gridDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        .onAppear { shownMonth = selection }
        .onChange(of: selection) { newValue in
            if !calendar.isDate(newValue, equalTo: shownMonth, toGranularity: .month) {
                shownMonth = newValue
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: shownMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)

        return Button {
            selection = combineKeepingTime(day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 15, weight: isToday || isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : (isToday ? .accentColor : (inMonth ? .primary : .secondary.opacity(0.5))))
                .frame(width: 34, height: 34)
                .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Short weekday names, starting on the user's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Always 6 weeks, so the grid does not jump in height between months.
    private var gridDays: [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: shownMonth)?.start else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -lead, to: monthStart) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func moveMonth(_ step: Int) {
        if let next = calendar.date(byAdding: .month, value: step, to: shownMonth) {
            shownMonth = next
        }
    }

    private func combineKeepingTime(_ day: Date) -> Date {
        EventFormat.combine(day: day, time: selection, calendar: calendar)
    }
}

private struct EventRow: View {
    let event: EventItem
    let isNow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(event.title).font(.body.weight(.semibold)).lineLimit(1)
                if isNow {
                    Text("NOW")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
            }
            Text("\(EventFormat.dayText(event.startDate)) · \(EventFormat.timeRangeText(event))")
                .font(.caption)
                .foregroundColor(.secondary)
            if !event.alertMinutes.isEmpty {
                Label(event.alertMinutes.map(EventFormat.alertText).joined(separator: ", "), systemImage: "bell")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
