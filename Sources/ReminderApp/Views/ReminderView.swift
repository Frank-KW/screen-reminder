import AppKit
import SwiftUI

struct ReminderView: View {
    @ObservedObject var store: TaskStore
    var onExit: () -> Void

    @EnvironmentObject private var worldClocks: WorldClockStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let palette: [Color] = [
        Color(red: 0.43, green: 0.75, blue: 0.98),
        Color(red: 0.56, green: 0.84, blue: 0.67),
        Color(red: 0.80, green: 0.66, blue: 0.98),
        Color(red: 0.98, green: 0.68, blue: 0.48),
        Color(red: 0.96, green: 0.55, blue: 0.67)
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let activeTask = store.activeTask(at: context.date)
                let accent = accentColor(for: activeTask)
                let taskImage = activeTask.flatMap { store.image(for: $0) }
                let protectionSeed = DisplayProtection.seed(for: activeTask?.id)
                let contentOffset = DisplayProtection.offset(
                    at: context.date,
                    canvasSize: proxy.size,
                    seed: protectionSeed,
                    edgeAnchored: taskImage != nil,
                    reduceMotion: reduceMotion
                )

                ZStack {
                    focusBackground(
                        accent: accent,
                        image: taskImage,
                        availableSize: proxy.size
                    )

                    VStack(spacing: 0) {
                        focusToolbar(date: context.date)
                            .padding(.horizontal, 30)
                            .padding(.top, 24)
                            .offset(DisplayProtection.offset(
                                at: context.date,
                                canvasSize: proxy.size,
                                seed: protectionSeed + 17,
                                reduceMotion: reduceMotion,
                                amplitudeScale: 0.22
                            ))

                        Group {
                            if let activeTask {
                                activeTaskContent(
                                    activeTask,
                                    date: context.date,
                                    accent: accent,
                                    availableSize: proxy.size,
                                    usesPhotoBackground: taskImage != nil
                                )
                            } else {
                                clearScheduleContent(accent: accent)
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: taskImage == nil ? .center : .bottomLeading
                        )
                        .padding(.bottom, taskImage == nil ? 0 : 28)
                        .offset(contentOffset)

                        if worldClocks.showsInDisplay, !worldClocks.clocks.isEmpty {
                            WorldClockStrip(
                                clocks: worldClocks.clocks,
                                date: context.date,
                                canvasSize: proxy.size
                            )
                            .padding(.top, 14)
                            .padding(.bottom, 18)
                            .offset(DisplayProtection.offset(
                                at: context.date,
                                canvasSize: proxy.size,
                                seed: protectionSeed + 47,
                                reduceMotion: reduceMotion,
                                amplitudeScale: 0.2
                            ))
                        }

                        Label("Display protection active  •  Press Esc to return", systemImage: "shield.lefthalf.filled")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.42))
                            .padding(.bottom, 24)
                            .offset(DisplayProtection.offset(
                                at: context.date,
                                canvasSize: proxy.size,
                                seed: protectionSeed + 31,
                                reduceMotion: reduceMotion,
                                amplitudeScale: 0.18
                            ))
                    }
                }
                .animation(.easeInOut(duration: 0.45), value: activeTask?.id)
            }
        }
    }

    @ViewBuilder
    private func focusBackground(
        accent: Color,
        image: NSImage?,
        availableSize: CGSize
    ) -> some View {
        if let image {
            TaskPhotoBackdrop(
                image: image,
                accent: accent,
                availableSize: availableSize
            )
        } else {
            ZStack {
                Color(red: 0.025, green: 0.030, blue: 0.045)

                LinearGradient(
                    colors: [accent.opacity(0.18), .clear, accent.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [accent.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 30,
                    endRadius: 620
                )
            }
            .ignoresSafeArea()
        }
    }

    private func focusToolbar(date: Date) -> some View {
        HStack(alignment: .top) {
            Button(action: onExit) {
                Label("Exit Focus Display", systemImage: "xmark")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Return to your reminder list (Esc)")

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.56))
            }
            .foregroundColor(.white)
        }
    }

    private func activeTaskContent(
        _ task: TaskItem,
        date: Date,
        accent: Color,
        availableSize: CGSize,
        usesPhotoBackground: Bool
    ) -> some View {
        let nowSeconds = TimeUtils.secondsSinceMidnight(for: date)
        let progress = TimeUtils.progress(
            startSeconds: task.startSeconds,
            endSeconds: task.endSeconds,
            nowSeconds: nowSeconds
        )

        return VStack(
            alignment: usesPhotoBackground ? .leading : .center,
            spacing: usesPhotoBackground ? 18 : 24
        ) {
            Text("IN PROGRESS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundColor(accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accent.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule().stroke(accent.opacity(0.25))
                }

            Text(task.title)
                .font(.system(
                    size: titleFontSize(for: availableSize, usesPhotoBackground: usesPhotoBackground),
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(usesPhotoBackground ? .leading : .center)
                .lineLimit(3)
                .minimumScaleFactor(0.45)
                .frame(
                    maxWidth: min(availableSize.width * (usesPhotoBackground ? 0.68 : 0.78), 1120),
                    alignment: usesPhotoBackground ? .leading : .center
                )
                .contentTransition(.opacity)
                .shadow(color: .black.opacity(usesPhotoBackground ? 0.48 : 0), radius: 16, y: 5)

            HStack(spacing: 10) {
                metadataPill(task.timeRangeText, systemImage: "clock")
                metadataPill(task.repeatSummary, systemImage: "repeat")
            }

            if task.startSeconds != task.endSeconds {
                VStack(spacing: 9) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(accent.gradient)
                                .frame(width: max(8, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text(TimeUtils.timeString(from: task.startSeconds))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .foregroundColor(.white.opacity(0.72))
                        Spacer()
                        Text(TimeUtils.timeString(from: task.endSeconds))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.42))
                }
                .frame(
                    maxWidth: min(availableSize.width * 0.46, 640),
                    alignment: usesPhotoBackground ? .leading : .center
                )
            }
        }
        .padding(.horizontal, usesPhotoBackground ? 58 : 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active task: \(task.title), \(task.timeRangeText), \(task.repeatSummary)")
    }

    private func clearScheduleContent(accent: Color) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(accent)
            }
            .frame(width: 86, height: 86)

            VStack(spacing: 10) {
                Text("Nothing needs your attention")
                    .font(.system(size: 50, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Your schedule is clear right now. Take a breath.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.52))
            }

            if !store.tasks.isEmpty {
                Text("\(store.tasks.count) scheduled \(store.tasks.count == 1 ? "reminder" : "reminders")")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.white.opacity(0.50))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 40)
    }

    private func metadataPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundColor(.white.opacity(0.66))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.08))
            }
    }

    private func titleFontSize(for size: CGSize, usesPhotoBackground: Bool) -> CGFloat {
        if usesPhotoBackground {
            return min(max(size.width * 0.046, 42), 82)
        }
        return min(max(size.width * 0.062, 54), 108)
    }

    private func accentColor(for task: TaskItem?) -> Color {
        guard let task else { return palette[1] }
        let seed = task.id.uuidString.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[seed]
    }
}

enum DisplayProtection {
    private static let reducedMotionPositions: [(x: CGFloat, y: CGFloat)] = [
        (-1, -1), (0, 1), (1, 0), (-1, 1), (1, -1),
        (0, 0), (-1, 0), (1, 1), (0, -1)
    ]

    static func seed(for taskID: UUID?) -> Int {
        guard let taskID else { return 0 }
        return taskID.uuidString.unicodeScalars.reduce(0) {
            (($0 * 31) + Int($1.value)) & 0x7fff_ffff
        }
    }

    static func offset(
        at date: Date,
        canvasSize: CGSize,
        seed: Int = 0,
        edgeAnchored: Bool = false,
        reduceMotion: Bool = false,
        amplitudeScale: CGFloat = 1
    ) -> CGSize {
        let maxX = min(max(canvasSize.width * 0.065, 18), 96) * amplitudeScale
        let maxY = min(max(canvasSize.height * 0.055, 14), 54) * amplitudeScale
        let xWave: CGFloat
        let yWave: CGFloat

        if reduceMotion {
            let interval = Int(floor(date.timeIntervalSinceReferenceDate / 300))
            let index = positiveModulo(interval + seed, reducedMotionPositions.count)
            let position = reducedMotionPositions[index]
            xWave = position.x
            yWave = position.y
        } else {
            let phase = Double(positiveModulo(seed, 360)) * .pi / 180
            let time = date.timeIntervalSinceReferenceDate
            xWave = CGFloat(sin((time / 83) + phase))
            yWave = CGFloat(sin((time / 107) + (phase * 1.7)))
        }

        if edgeAnchored {
            return CGSize(
                width: ((xWave + 1) / 2) * maxX,
                height: -((yWave + 1) / 2) * maxY
            )
        }
        return CGSize(width: xWave * maxX, height: yWave * maxY)
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

private struct TaskPhotoBackdrop: View {
    let image: NSImage
    let accent: Color
    let availableSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isZoomed = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: availableSize.width, height: availableSize.height)
            .scaleEffect(reduceMotion ? 1.02 : (isZoomed ? 1.075 : 1.02))
            .clipped()
            .overlay(Color.black.opacity(0.18))
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.42), location: 0),
                        .init(color: .clear, location: 0.36),
                        .init(color: .clear, location: 0.56),
                        .init(color: .black.opacity(0.72), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    colors: [accent.opacity(0.18), .clear],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
            .ignoresSafeArea()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                    isZoomed = true
                }
            }
    }
}
