# Paperpin

Paperpin is a native sticky-note board for macOS. Keep multiple notes in view, mix freeform text with checklists, and check off tasks to move them to the archive. Restore a task to put it back on its original sticky.

The menu bar shows the pending count and can also show the next task’s title. Click the icon or press **Control–Option–Space** to add or complete tasks without opening the board. Notes and unfinished drafts save automatically on your Mac.

## Apple Reminders

Choose **Connect Apple Reminders…** in a note’s **•••** menu, allow macOS Reminders access, and choose a list. The picker shows list and account names and suggests **Main Work** when available. One note and one list can be connected at a time. The connection adds **Tasks** and **Apple Reminders Tasks** tabs to that note on the board and desktop; each presentation remembers its own selection. Narrow notes use a compact selector.

Paperpin can **view and complete** pending reminders. It shows expandable notes, due dates, and recurring indicators. Creation, editing, deletion, recurrence settings, and completed history remain in Apple Reminders. Completing an Apple reminder does not add it to Paperpin’s archive. Local Paperpin tasks remain separate and keep their existing drag ordering.

Every view uses the same order: overdue reminders (including recurring ones), dated non-recurring reminders, undated non-recurring reminders, then remaining recurring reminders. Dated groups show the earliest due date first. Date-only items become overdue after their due day ends in the applicable time zone. Ties are stable by creation date, title, and identifier.

The quick panel has an **Apple Reminders · [list name]** section. Its pending count and the menu-bar count include both sources; the optional next-task title keeps local tasks first. Board search includes connected reminder titles and notes, opening the Reminders tab for reminder-only matches.

Sync uses Apple’s [EventKit framework](https://developer.apple.com/documentation/eventkit) and the Mac’s local Reminders database. Apple handles iCloud delivery; a local save does not imply another device has received it yet. Refreshes follow app activation, wake, manual refresh, and [EventKit change notifications](https://developer.apple.com/documentation/eventkit/updating-with-notifications), with no polling. A one-shot timer updates overdue ordering at the next relevant deadline. Permission loss clears displayed reminders; missing lists, read-only lists, and failures have explicit states. Failed completion stays visible with a retry action.

Use **Apple Reminders → Change List…** or **Disconnect** in the note menu. Renames preserve the connection by identifier; a removed/replaced list requires reselection. Disconnecting or deleting the host note never deletes Apple reminders. Connections and tab preferences live outside `Board.json`; reminders are not copied into the note file. Each Mac needs its own connection and macOS permission. macOS 13 uses the legacy permission flow; macOS 14+ uses full Reminders access.

## Reorder tasks

Hover over a task and drag the small grip at its right edge. A line shows where it will land; release to move it within that note. This works on the board, in desktop notes, and in the quick panel, with the same order immediately reflected everywhere. Hold near the top or bottom of a long list to scroll while dragging. Press Escape or drop outside the list to cancel.

For precise moves, right-click the grip and choose **Move Up** or **Move Down**. A focused grip also supports the arrow keys, Return for its menu, and VoiceOver move actions. Reordering preserves task text, unfinished drafts, and completion/archive behavior. Tasks stay within their original note; archived tasks and the task-entry field cannot be dragged.

## Minimal desktop notes

Choose **View → Minimal Mode** for separate, resizable Stickies-style windows. Use a sticky’s **Show on desktop** action to add it. Notes stay behind normal windows across desktop Spaces; click a note to edit it. Switching applications returns it to the desktop.

Each window has a small drag strip, a plain text editor, and optional checklist rows. The note field grows with its text and shrinks to a “Write a note…” hint when empty. Tasks start directly below it and use the remaining space; long notes scroll without pushing the task list away. Text, checkbox alignment, row spacing, and task-entry controls match the board, including when a task wraps onto several lines. Its ••• menu offers Add Task, Rename, Paper Color, and Open in Board. Closing a window hides that note without deleting it. Open the full board from the menu bar at any time; it shares the same notes and archive. Window placement and your chosen notes return when you reopen Paperpin.

## Board layout

The full board uses a normal window with standard close, minimize, and zoom controls. Choose **View → Keep Board on Top** when you want it above other application windows. Choose **Open board** in the menu bar panel to reopen or restore it from the Dock.

Press **Control–Command–S** to hide or show the sidebar. The sidebar and Minimal Mode controls are also available in the menu bar panel’s **•••** menu. Opening the board alongside minimal notes or switching between modes preserves its floating and sidebar preferences.

## Appearance and launch

**View → Liquid Glass** changes the entire app’s appearance with pearl light surfaces, deep slate dark surfaces, rounded cards, blue-violet controls, and restrained note-color accents. It is off by default and temporarily pauses during Low Power Mode or Reduce Transparency. It requires macOS 26+ with native glass support, including supported Intel Macs. On older or unsupported systems, the toggle is greyed out and unchecked in every menu, an explanation is shown, and Paperpin uses its ordinary opaque appearance. A saved glass preference is retained for a later supported OS, without applying any glass or frosted effect while unsupported. The [Liquid Glass Studio](https://github.com/iyinchao/liquid-glass-studio) project is the visual reference; Paperpin uses native AppKit rendering without its web renderer or continuous animation loop.

**Paperpin → Launch at Login** registers the installed app using macOS Service Management. If approval is needed, use **Login Items Settings…**. Disabling it in System Settings remains respected. Register the installed app, not a temporary build; test builds never register login items. Launch at login does not prevent sleep or restart an app that was explicitly quit.

## Saving and energy use

Edits appear immediately. Text saves coalesce after 350 ms of inactivity and at most two seconds of continuous typing. Note/task structure changes submit immediately; closing editors, switching applications, sleeping, and quitting flush pending work. Atomic saves and unreadable-file protection remain in place. The board reports pending, saving, saved, or failed state, and desktop notes show save errors.

There is no repeating autosave or animation loop. The full board is created only when needed, hidden quick-panel content is released, and each desktop editor observes its own note. Glass can still require compositor work; use opaque mode for the lightest rendering.

## Build and run

Use a Mac with Swift and a macOS 26+ SDK. The build script creates a universal app for Apple silicon and Intel Macs running macOS 13 or later. It prefers `/Applications/Xcode.app` when installed, without changing the system-wide developer selection; set `DEVELOPER_DIR` to override this choice. It probes SwiftUI compiler support and can fall back to an installed macOS 26 SDK if a newer Command Line Tools SDK lacks the required macro plugin. Set `PAPERPIN_SDKROOT` to select a specific working SDK. Linker warnings fail the release build, including warnings about missing Intel compatibility libraries.

```sh
./build.zsh
open .build/Paperpin.app
```

You can copy the built app into Applications. Your board remains at `~/Library/Application Support/Paperpin/Board.json`, using the original version-1 format. Desktop window geometry and appearance preferences live separately in UserDefaults.

For a first local installation, launch the installed app with `--setup-desktop --enable-login-item` to select minimal mode and request login registration. The setup flag applies once and never overrides a later mode choice. Login registration reports its actual result; macOS may require user approval.

## Installers and sharing

Run `./package.zsh` to build a fresh universal app and a drag-to-Applications DMG under `.build/distribution/`. An optional output directory is accepted as its first argument. The script refuses to overwrite an existing installer, verifies both architecture signatures, mounts the image, checks a copied app, and produces a SHA-256 checksum. It packages only the build output and installation instructions. Personal notes, preferences, and login registration are not included or changed.

The free build is **ad hoc signed, not Apple-notarized**. Recipients may need to open **System Settings → Privacy & Security → Open Anyway** once after attempting to open Paperpin. Apple Developer ID signing and notarization require Apple Developer Program membership; repackaging alone cannot replace them. See [Apple's first-open instructions](https://support.apple.com/en-us/102445).

Share a **browser download link**, including when sending it through WhatsApp or Telegram. Recipients should open the link in Safari and download there, rather than receive the DMG as a chat attachment. Some transfer apps can apply a restrictive quarantine flag that prevents both launch and the normal Open Anyway option, even to notarized apps; Apple describes this [transfer-related block](https://developer.apple.com/forums/thread/767612). The release link and Safari route avoid relying on the chat app to create the installer file. Affected recipients should replace the blocked app with a fresh browser download and use the normal macOS approval screen. Do not delete their Paperpin data folder.

The installer includes the same graphical steps in **Read me first.txt**. A free DMG cannot promise approval-free first launch or override restrictions on managed Macs.

## Tests

Run storage, persistence, appearance-policy, and login-state checks from the repository root. They use isolated files and fake login services.

```sh
./Tests/run-checks.zsh
```

The UI checks use a separate test app and temporary board. Quit Paperpin before running keyboard-shortcut checks so the test app can register the shortcut.

```sh
./Tests/run-ui.zsh
PAPERPIN_CHECK_LAYOUT=1 ./Tests/run-ui.zsh
PAPERPIN_CHECK_MINIMAL=1 ./Tests/run-ui.zsh
PAPERPIN_CHECK_POLISH=1 ./Tests/run-ui.zsh
PAPERPIN_CHECK_GLASS_UNAVAILABLE=1 ./Tests/run-ui.zsh
PAPERPIN_CHECK_REORDER=1 ./Tests/run-ui.zsh
PAPERPIN_CHECK_REMINDERS=1 ./Tests/run-ui.zsh
```

The layout suite checks normal board controls, floating, sidebar, minimize/reopen behavior, preference restoration, and migration away from the retired whole-board desktop setting. The minimal-mode suite checks native editing, shared notes, window restoration, fullscreen transitions, simulated display removal, and lifecycle saves. Screenshots and logs are written under `.build/tests/`.

The glass-unavailable suite simulates absent native support in the isolated QA app, checking disabled controls, opaque rendering, and preserved notes/preferences across relaunch. The simulation override is excluded from release builds.

The reorder suite exercises native drop callbacks with actual row geometry across all three views, every task position, invalid drops, cancellation, scrolling, accessibility actions, shared edits, and relaunch. These controller checks complement a real pointer-drag check; they do not synthesize a WindowServer drag. Run `PAPERPIN_REORDER_INTERACTIVE=1 ./Tests/run-ui.zsh` to open isolated sample notes for that manual check.

The Reminders unit suite uses a fake client to exercise ordering, time zones, permission changes, stale fetches, recurrence identity, failed completion, independent tabs, and notification coalescing. The window suite uses synthetic reminders only; it never requests system permission or registers login items. `PAPERPIN_REMINDERS_INTERACTIVE=1 ./Tests/run-ui.zsh` opens sample reminders for real UI checks.

`Tests/LiveRemindersChecks.swift` is a separate, explicitly launched test app for real EventKit validation. It requests its own permission, creates a clearly labeled temporary list, tests one-time/weekly/monthly reminders and external changes, and removes that list. It is never compiled into the distributed app. Do not use real personal reminders for completion tests.

`Tools/TypingBenchmark.swift` compares atomic save counts against the historical store (compile the historical version with `-D PAPERPIN_BASELINE`). `Tools/measure-idle.py PID --output result.json` measures five minutes of process CPU, wakeups, memory, and disk counters after a 30-second warmup. These process counters do not isolate WindowServer/GPU energy or predict battery life.
