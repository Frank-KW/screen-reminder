import SwiftUI

// MARK: - Clock face

/// A round analog clock face, white by day and dark by night.
struct AnalogClockFace: View {
    let angles: WorldClockMath.HandAngles
    let isDaytime: Bool
    var showsSecondHand = true
    var showsNumbers = true

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let face = isDaytime ? Color(white: 0.97) : Color(white: 0.11)
            let ink = isDaytime ? Color(white: 0.08) : Color(white: 0.94)

            ZStack {
                Circle().fill(face)
                Circle().stroke(Color.white.opacity(isDaytime ? 0 : 0.14), lineWidth: max(1, size * 0.012))

                if showsNumbers {
                    ForEach(1...12, id: \.self) { number in
                        let angle = Double(number) * .pi / 6
                        Text("\(number)")
                            .font(.system(size: size * 0.125, weight: .medium, design: .rounded))
                            .foregroundColor(ink)
                            .offset(x: sin(angle) * radius * 0.76, y: -cos(angle) * radius * 0.76)
                    }
                } else {
                    ForEach(0..<12, id: \.self) { index in
                        Capsule()
                            .fill(ink.opacity(0.5))
                            .frame(width: max(1, size * 0.03), height: size * 0.09)
                            .offset(y: -radius * 0.8)
                            .rotationEffect(.degrees(Double(index) * 30))
                    }
                }

                hand(angle: angles.hour, length: radius * 0.5, width: size * 0.05, color: ink)
                hand(angle: angles.minute, length: radius * 0.78, width: size * 0.038, color: ink)
                if showsSecondHand {
                    hand(angle: angles.second, length: radius * 0.86, width: max(1, size * 0.014), color: .orange)
                }
                Circle()
                    .fill(showsSecondHand ? Color.orange : ink)
                    .frame(width: size * 0.07, height: size * 0.07)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func hand(angle: Double, length: CGFloat, width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

// MARK: - Full-screen strip

/// One city on the full-screen display: face, city name, and "Tomorrow, +8 hrs".
struct WorldClockTile: View {
    let clock: WorldClock
    let date: Date
    let faceSize: CGFloat

    var body: some View {
        let zone = clock.timeZone ?? .current
        let relative = WorldClockMath.relativeText(for: zone, at: date)
        let time = WorldClockMath.timeText(in: zone, at: date)

        VStack(spacing: 7) {
            AnalogClockFace(
                angles: WorldClockMath.handAngles(in: zone, at: date),
                isDaytime: WorldClockMath.isDaytime(in: zone, at: date),
                showsNumbers: faceSize >= 84
            )
            .frame(width: faceSize, height: faceSize)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            Text(clock.cityName)
                .font(.system(size: max(12, faceSize * 0.14), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(relative)
                .font(.system(size: max(10, faceSize * 0.1), weight: .medium))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: faceSize + 34)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock.cityName), \(time), \(relative)")
    }
}

/// A row of city clocks sized to fit the screen.
struct WorldClockStrip: View {
    let clocks: [WorldClock]
    let date: Date
    let canvasSize: CGSize

    private let spacing: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(clocks) { clock in
                WorldClockTile(clock: clock, date: date, faceSize: faceSize)
            }
        }
    }

    private var faceSize: CGFloat {
        let count = CGFloat(max(clocks.count, 1))
        let usableWidth = canvasSize.width * 0.88
        let byWidth = (usableWidth - spacing * (count - 1)) / count - 34
        let byHeight = canvasSize.height * 0.15
        return min(140, max(52, min(byWidth, byHeight)))
    }
}

// MARK: - Manage cities

/// Sheet where the user adds, edits, reorders, and removes cities.
struct WorldClocksManagerView: View {
    @EnvironmentObject private var store: WorldClockStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Equatable {
        case list
        case add
        case edit(WorldClock)
    }

    @State private var mode: Mode = .list

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch mode {
            case .list:
                listContent
            case .add:
                CityEditorView(
                    title: "Add City",
                    initialName: "",
                    initialTimeZoneID: nil,
                    onCancel: { mode = .list },
                    onSave: { name, zoneID in
                        store.add(cityName: name, timeZoneID: zoneID)
                        mode = .list
                    }
                )
            case .edit(let clock):
                CityEditorView(
                    title: "Edit City",
                    initialName: clock.cityName,
                    initialTimeZoneID: clock.timeZoneID,
                    onCancel: { mode = .list },
                    onSave: { name, zoneID in
                        store.update(clock.id, cityName: name, timeZoneID: zoneID)
                        mode = .list
                    }
                )
            }
        }
        .padding(24)
        .frame(width: 580, height: 560)
    }

    private var listContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("World Clocks")
                    .font(.title2.bold())
                Text("Cities shown along the bottom of the full-screen display. Up to \(WorldClockStore.maxClocks).")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Toggle("Show clocks on the full-screen display", isOn: Binding(
                get: { store.showsInDisplay },
                set: { store.setShowsInDisplay($0) }
            ))
            .toggleStyle(.switch)

            Divider()

            if store.clocks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.accentColor)
                    Text("No cities yet")
                        .font(.headline)
                    Text("Add a city to see its time next to your reminders.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(Array(store.clocks.enumerated()), id: \.element.id) { index, clock in
                                clockRow(clock, index: index, date: context.date)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button {
                    mode = .add
                } label: {
                    Label("Add City", systemImage: "plus")
                }
                .disabled(!store.canAddMore)
                .help(store.canAddMore ? "Add a city clock" : "You can show up to \(WorldClockStore.maxClocks) cities")

                if !store.canAddMore {
                    Text("Limit reached")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func clockRow(_ clock: WorldClock, index: Int, date: Date) -> some View {
        let zone = clock.timeZone ?? .current
        return HStack(spacing: 12) {
            AnalogClockFace(
                angles: WorldClockMath.handAngles(in: zone, at: date),
                isDaytime: WorldClockMath.isDaytime(in: zone, at: date),
                showsSecondHand: false,
                showsNumbers: false
            )
            .frame(width: 38, height: 38)
            .overlay(Circle().stroke(Color.primary.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(clock.cityName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(WorldClockMath.relativeText(for: zone, at: date)) · \(clock.timeZoneID)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(WorldClockMath.timeText(in: zone, at: date))
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)

            HStack(spacing: 2) {
                iconButton("chevron.up", help: "Move \(clock.cityName) left") {
                    store.move(clock.id, by: -1)
                }
                .disabled(index == 0)

                iconButton("chevron.down", help: "Move \(clock.cityName) right") {
                    store.move(clock.id, by: 1)
                }
                .disabled(index == store.clocks.count - 1)

                iconButton("pencil", help: "Edit \(clock.cityName)") {
                    mode = .edit(clock)
                }

                iconButton("trash", help: "Remove \(clock.cityName)") {
                    store.delete(clock.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Search for a city, pick it, and optionally rename its label.
private struct CityEditorView: View {
    let title: String
    let initialName: String
    let initialTimeZoneID: String?
    let onCancel: () -> Void
    let onSave: (String, String) -> Void

    @State private var query = ""
    @State private var selection: CitySuggestion?
    @State private var name = ""
    @FocusState private var isSearchFocused: Bool

    private static let allSuggestions = WorldClockMath.allSuggestions()

    private var results: [CitySuggestion] {
        WorldClockMath.search(query, in: Self.allSuggestions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            TextField("Search a city or time zone, e.g. Tokyo", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isSearchFocused)

            ScrollViewReader { reader in
                List(results, selection: $selection) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .font(.body.weight(.medium))
                            Text(suggestion.regionText.isEmpty ? suggestion.timeZoneID : suggestion.regionText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if let zone = TimeZone(identifier: suggestion.timeZoneID) {
                            Text(WorldClockMath.timeText(in: zone, at: Date()))
                                .font(.callout.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .tag(suggestion)
                    .id(suggestion.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .overlay {
                    if results.isEmpty {
                        Text("No city matches \"\(query)\"")
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    if let selection {
                        reader.scrollTo(selection.id, anchor: .center)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Label")
                    .foregroundColor(.secondary)
                TextField("City name shown on the clock", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }

            HStack {
                if let selection {
                    Label(selection.timeZoneID, systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Pick a city from the list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
        }
        .onAppear {
            name = initialName
            if let initialTimeZoneID {
                selection = Self.allSuggestions.first {
                    $0.timeZoneID == initialTimeZoneID && $0.name == initialName
                } ?? Self.allSuggestions.first { $0.timeZoneID == initialTimeZoneID }
            }
            isSearchFocused = true
        }
        .onChange(of: selection) { [selection] newValue in
            // Follow the picked city unless the user typed their own label.
            guard let newValue else { return }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == selection?.name {
                name = newValue.name
            }
        }
    }

    private func save() {
        guard let selection else { return }
        onSave(name, selection.timeZoneID)
    }
}
