import SwiftUI

struct RepeatDaysPicker: View {
    @Binding var selectedDays: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REPEAT")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.accentColor)
            }

            HStack(spacing: 6) {
                ForEach(Weekday.ordered) { day in
                    dayButton(day)
                }
            }

            HStack(spacing: 7) {
                presetButton("Every day", isSelected: selectedDays.isEmpty) {
                    selectedDays = []
                }
                presetButton("Weekdays", isSelected: selectedDays == Weekday.weekdaySet) {
                    selectedDays = Weekday.weekdaySet
                }
                presetButton("Weekends", isSelected: selectedDays == Weekday.weekendSet) {
                    selectedDays = Weekday.weekendSet
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedDays)
    }

    private var summary: String {
        TaskItem(title: "", startSeconds: 0, endSeconds: 0, repeatDays: selectedDays.sorted()).repeatSummary
    }

    private func dayButton(_ day: Weekday) -> some View {
        let isSelected = selectedDays.contains(day.rawValue)
        return Button {
            toggle(day.rawValue)
        } label: {
            Text(String(day.shortLabel.prefix(1)))
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundColor(isSelected ? .white : .primary)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(day.shortLabel)
        .accessibilityLabel(day.shortLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func presetButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .background(
                    isSelected ? Color.accentColor.opacity(0.11) : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10))
                }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ day: Int) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}
