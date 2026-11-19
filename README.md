# Screen Reminder

A Mac app that fills the screen with what you should be doing right now.

- Add tasks with a start time, an end time, repeat days and an optional photo.
- Press **Open Display** (⇧⌘R). The screen shows the task that is due now, or "Nothing needs your attention".
- Add up to 8 **world clocks** (⇧⌘K). They sit along the bottom of the display, like the Mac and iPhone world clock widget.
- The display drifts slowly so nothing burns into the screen.

Needs macOS 13 Ventura or later.

## Install

1. Open the [Releases](../../releases) page and download the newest `Screen-Reminder-x.y.z.zip`.
2. Double-click the zip. Drag **Screen Reminder** into **Applications**.
3. Open it.

**Version 1.0.0 is not yet signed by Apple**, so the first time you open it macOS says it "could not verify" the app. To open it anyway, once per Mac:

1. Click **Done** on the warning.
2. Open **System Settings → Privacy & Security** and scroll down.
3. Next to "Screen Reminder was blocked", click **Open Anyway**, then confirm.

After that it opens normally. Later versions will be signed and checked by Apple, with no warning.

## Build from source

```bash
swift test
```

```bash
open ReminderApp.xcodeproj
```

Then press Run in Xcode.

## Releasing

You need, once per Mac:

1. A **Developer ID Application** certificate in your keychain. Only the team's Account Holder can create one: Xcode → Settings → Apple Accounts → (account) → (team) → Manage Certificates → + → Developer ID Application, or developer.apple.com → Certificates → +. Export it with its private key as a .p12 and open that on the release Mac.
2. A saved notary login. Make an app-specific password at account.apple.com, then run this and paste it when asked:

   ```bash
   xcrun notarytool store-credentials screen-reminder-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

Then for each release:

```bash
scripts/release.sh 1.0.0
```

```bash
gh release create v1.0.0 "dist/Screen-Reminder-1.0.0.zip" --title "Screen Reminder 1.0.0" --notes "First release."
```

Without a Developer ID certificate, `scripts/release.sh 1.0.0 --unsigned` makes the same zip without Apple's check. People then need the "Open Anyway" step above.
