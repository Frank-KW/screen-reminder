import SwiftUI

struct TimeBlockSettingsView: View {
    @EnvironmentObject private var timeBlockSettings: TimeBlockSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Time Blocks")
                    .font(.title2.bold())
                Text("Set the times offered when you create or edit a reminder.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("BLOCK")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("START")
                        Text("END")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                    Divider()
                        .gridCellColumns(3)

                    ForEach(TimeBlock.allCases) { block in
                        GridRow {
                            Label(block.displayName, systemImage: block.symbolName)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            DatePicker(
                                "\(block.displayName) start",
                                selection: timeBinding(for: block, keyPath: \.startSeconds),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)

                            DatePicker(
                                "\(block.displayName) end",
                                selection: timeBinding(for: block, keyPath: \.endSeconds),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.trailing, 8)
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ranges may cross midnight.")
                    Text("Changes apply when a preset is selected or reapplied; saved reminder times stay unchanged.")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                Button("Restore UK Defaults") {
                    timeBlockSettings.restoreUKDefaults()
                }
            }
        }
        .padding(24)
        .frame(width: 600, height: 530)
    }

    private func timeBinding(
        for block: TimeBlock,
        keyPath: WritableKeyPath<TimeBlockRange, Int>
    ) -> Binding<Date> {
        Binding(
            get: {
                TimeUtils.date(from: timeBlockSettings.range(for: block)[keyPath: keyPath])
            },
            set: { date in
                var range = timeBlockSettings.range(for: block)
                range[keyPath: keyPath] = TimeUtils.secondsSinceMidnight(for: date)
                timeBlockSettings.update(range, for: block)
            }
        )
    }
}
