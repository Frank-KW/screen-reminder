import AppKit
import UniformTypeIdentifiers

/// The Save and Open windows and the "are you sure?" box for backups.
enum BackupController {
    static func export(using service: BackupService) {
        let panel = NSSavePanel()
        panel.title = "Export Backup"
        panel.message = "Saves your events, reminders, photos, time blocks and world clocks in one file."
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = BackupCodec.suggestedFileName()
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = service.makeBackup()
        do {
            try BackupCodec.encode(file).write(to: url, options: .atomic)
            inform(
                "Backup saved",
                "\(file.summary)\n\nSaved to \(url.path)"
            )
        } catch {
            inform("Backup not saved", error.localizedDescription, style: .warning)
        }
    }

    static func restore(using service: BackupService) {
        let panel = NSOpenPanel()
        panel.title = "Restore from Backup"
        panel.message = "Choose a Screen Reminder backup file."
        panel.prompt = "Choose Backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let file: BackupFile
        do {
            file = try BackupCodec.decode(Data(contentsOf: url))
        } catch {
            inform("Backup not restored", error.localizedDescription, style: .warning)
            return
        }

        let ask = NSAlert()
        ask.messageText = "Restore this backup?"
        ask.informativeText = """
        Made \(file.exportedAt.formatted(date: .abbreviated, time: .shortened)). It holds \(file.summary).

        Restoring replaces what is in the app now. A copy of your current data is saved first, in case you change your mind.
        """
        ask.addButton(withTitle: "Restore Events Only")
        ask.addButton(withTitle: "Restore Everything")
        ask.addButton(withTitle: "Cancel")
        ask.buttons.last?.keyEquivalent = "\u{1b}"

        let scope: RestoreScope
        switch ask.runModal() {
        case .alertFirstButtonReturn: scope = .eventsOnly
        case .alertSecondButtonReturn: scope = .everything
        default: return
        }

        let safety: URL
        do {
            safety = try service.writeSafetyCopy(into: BackupService.safetyFolder)
        } catch {
            inform(
                "Backup not restored",
                "Your current data could not be saved first, so nothing was changed. \(error.localizedDescription)",
                style: .warning
            )
            return
        }

        do {
            let result = try service.restore(file, scope: scope)
            var lines = ["Restored \(result.events) event\(result.events == 1 ? "" : "s")."]
            if scope == .everything {
                lines.append("Restored \(result.tasks) reminder\(result.tasks == 1 ? "" : "s") and \(result.worldClocks) world clock\(result.worldClocks == 1 ? "" : "s").")
                if result.missingPhotos > 0 {
                    lines.append("\(result.missingPhotos) photo\(result.missingPhotos == 1 ? " was" : "s were") missing from the backup.")
                }
            }
            lines.append("Your old data is in \(safety.path)")
            inform("Backup restored", lines.joined(separator: "\n\n"))
        } catch {
            inform(
                "Restore stopped",
                "\(error.localizedDescription)\n\nYour old data is in \(safety.path)",
                style: .warning
            )
        }
    }

    private static func inform(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
