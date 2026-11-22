# Validation — Paperpin 1.4.0

Validated on 23 November 2026 on Apple silicon, macOS 27.0.1, using Xcode 27.2 / Swift 6.4.2. Both release architectures target macOS 13+.

The Reminders connection uses a serial EventKit adapter, immutable snapshots, and one shared store. It does not alter the version-1 board format. Only connection identifiers and independent tab preferences are persisted; reminders are not copied into `Board.json`. Completion re-fetches and validates the current occurrence, updates only completion state, and lets Apple generate the next recurring occurrence. Unrelated desktop note editors do not observe reminder item changes.

| Suite | Passing checks |
| --- | ---: |
| Existing storage, persistence, appearance, login, and task-ordering checks | 67 |
| Existing board, quick-panel, layout, desktop, polish, glass, and reorder window checks | 188 |
| Reminders ordering, permissions, connection, completion, and refresh checks | 49 |
| Reminders controller/window checks and relaunch | 21 |
| Real EventKit temporary-list checks | 12 |

All **337 checks passed**. The live and UI interaction checks below supplement the controller tests.

The existing storage, archive, desktop, layout, appearance, and task-reordering suites passed unchanged. The shortcut check also exposed an activation edge case: opening the quick panel now activates Paperpin before requesting keyboard focus.

Reminders checks cover overdue recurring tasks, stable ties, timed and date-only deadlines, floating/explicit time zones, DST, permission revocation and restoration, read-only lists, rename/removal/replacement, old-list and out-of-order replies, duplicate clicks, failures and retries, shared saving state, lifecycle completion draining, tab persistence, host-note deletion, search, burst coalescing, and settled inactivity. Unchanged connection preferences are compared by decoded value, avoiding JSON key-order-related writes.

The controller/window suite covers independent tabs and recreation, search-driven tab selection, shared quick-panel data, combined counts, local-first next titles, minimum-size windows, paper/glass rendering, lazy quick-panel release, shared completion, unchanged local tasks/archive, and relaunch. Native UI interactions were separately checked through the app: tab selection, expandable notes, reminder-note search, desktop completion, the corresponding board removal, and the updated quick-panel total. SwiftUI virtual controls were not exposed to the in-process accessibility probe on this OS; its initial unsuccessful attempts are not counted as passing UI interaction tests.

Real EventKit validation used a clearly labeled **Paperpin TEMPORARY sync test** list after the user granted access to the separate test app. One-time completion, concurrent note edits, restoration, and deletion passed. Weekly and monthly completions advanced to future occurrences while preserving notes and recurrence rules; stale completion attempts were rejected. The temporary list was removed. **No real Main Work reminder was completed or edited during testing.**

Synthetic screenshots were reviewed in light and dark paper/glass modes, including a 200-point-wide desktop note. Review images: [glass desktop](docs/images/reminders-desktop-glass-light.png), [paper desktop](docs/images/reminders-desktop-paper-light.png), [glass board](docs/images/reminders-board-glass-dark.png), and [quick panel](docs/images/reminders-quick-panel.png). The existing unavailable-glass suite also passed. Reduce Transparency/Low Power Mode remain covered by the existing appearance-policy tests; system-wide accessibility and power settings were not changed during this update.

A five-minute idle measurement of an optimized build with a synthetic connected desktop note, glass enabled, and the board closed recorded **0.0017% of one CPU core**, **49.2 MiB physical footprint**, **0 disk/logical write bytes**, **0 package-idle wakeups**, and **47 interrupt-wakeup counter increments**. `Board.json` was unchanged. Reminders diagnostics recorded no additional fetches or preference writes during the settled interval. The fixture isolates app-owned scheduling and rendering; it does not measure Apple's iCloud service overhead. These are process counters, not battery-life estimates, and exclude WindowServer/GPU attribution. No new typing-write comparison against an older release is claimed.

The universal DMG passed image verification, read-only mount, application copy, executable comparison, arm64/x86_64 architecture checks, macOS 13 minimum-target checks, and strict signature verification for both slices. It contains only the fresh app, Applications shortcut, and installation instructions. It is **ad hoc signed, not Apple-notarized**; recipients should download through a browser and use normal macOS first-open approval when required.

The DMG was installed at `/Applications/Paperpin.app` as **1.4.0 (10)**. The app reopened successfully, the user granted Reminders access and selected **Main Work**, and the existing **Tasks** note displayed the connection. A further orderly relaunch restored the same list and desktop tab. The personal `Board.json` bytes remained unchanged. Appearance, board/minimal mode, sidebar, next-task, and open-note settings were preserved; desktop sizes were identical and coordinates matched within one AppKit point. The existing launch-at-login registration remained **enabled, allowed, notified** in the system registry without toggling it. The previous app, notes, and preferences are backed up in `.build/pre-reminders-update-1.4.0/`.

Artifact: `Paperpin-1.4.0-universal.dmg`, **2,439,317 bytes**. SHA-256: `efd9841637bcf28fdc2384342e76300bbb2f938e7fe93ac101da1865f75b11f7`. A copy is also in Downloads.

Runtime testing used this Apple silicon Mac. Physical Intel and older macOS runtime checks were unavailable. A separate iCloud-device update, a forced offline network test, actual sleep/wake, and logout/login were not performed in this session; event-driven refresh paths and local database operations were verified without claiming remote-device delivery. No network connection was disabled and the user’s session was not interrupted for logout.

Local evidence: `.build/reminders-all-checks-final.log`, `.build/reminders-unit-final.log`, `.build/reminders-ui-final.log`, `.build/reminders-regression/`, `.build/live-reminders-checks.log`, `.build/reminders-energy.json`, `.build/reminders-energy-app.log`, and `.build/package-1.4.0.log`.

---

## Previous validation — Paperpin 1.3.5

Validated on 19 November 2026 on Apple silicon, macOS 27.0.1, with Xcode 27.2 / Swift 6.4.2. The universal app targets macOS 13+ and includes arm64 and x86_64 binaries.

Task rows now share a native drag handle across the board, desktop notes, and quick panel. Drops resolve task IDs against the current note and commit only when the position changes. The version-1 board format is unchanged. Native row bounds constrain drop targets, including on systems where a non-clipping view's visible rectangle extends across its parent list.

| Suite | Passing checks |
| --- | ---: |
| Storage, persistence, appearance, login policy, and task ordering | 67 |
| Board, quick panel, keyboard, and relaunch | 29 |
| Layout and preference migration | 25 |
| Desktop windows and restoration | 33 |
| Content sizing, checklist alignment, appearance, and relaunch | 25 |
| Unavailable native glass and relaunch | 21 |
| Native reorder callbacks, shared windows, scrolling, and relaunch | 55 |

All **255 checks passed**. The reorder suite covers every source task and final position in all three views, including wrapped text; beginning/end drops; stale, external, cross-note, and outside-list rejection; insertion-line cancellation; long-list scrolling in both directions; quick-panel retention during a drag and dismissal restoration; accessible move actions; closing/deleting the source; and saved order after relaunch. Storage checks verify one write per changed move, no writes for unchanged/invalid moves, latest unsaved text preservation, duplicate titles, archive position restoration, failed-save recovery, and legacy format loading.

The user tested real mouse dragging after the row-boundary correction and confirmed that moving tasks up and down works correctly in both the board and desktop note. Quick-panel destinations and drag lifecycle were exercised through native callbacks with actual window geometry. Pointer automation was unreliable and is not counted as a successful end-to-end quick-panel mouse test.

Opaque and glass screenshots were reviewed in light and dark appearances. Sample-note review images: [board with reorder grip](docs/images/task-reorder-board-glass.png) and [desktop with reorder grip](docs/images/task-reorder-desktop-glass.png). These screenshots contain synthetic notes only. Existing wrapped-checkbox alignment checks also passed.

The universal release compiled with linker warnings treated as errors and passed strict signature verification for both architectures. The DMG was verified, mounted read-only, copied out, and checked again for executable integrity, architectures, signature, and minimum OS. It includes an Applications shortcut and first-open instructions. The build remains **ad hoc signed, not Apple-notarized**; share the browser download link and use macOS's normal first-open approval if required.

Paperpin 1.3.5 was installed from this DMG at `/Applications/Paperpin.app`, launched successfully, and restored the existing desktop note with the new task handles. Note-file bytes and saved presentation preferences were unchanged after installation and launch. The existing enabled launch-at-login registration was restored and verified in the macOS background-item registry. A local backup of the previous app, notes, and preferences is in `.build/pre-reorder-update-1.3.5/`.

No repeating idle timer or autosave was added. The active drag alone receives native periodic destination updates for scrolling; its temporary subscriptions and insertion marker are cleared when it ends. Save checks verified no recurring writes after reordering settled. The historical five-minute energy comparison was not repeated for this feature; no new battery-life or compositor-energy claim is made.

Runtime checks used this Apple silicon Mac. Intel binaries were built and verified, but this version has not been run on a physical Intel Mac or an older macOS release. Logout/login was not performed.

Local evidence: `.build/reorder-checks.log`, `.build/reorder-ui-final.log`, `.build/reorder-regression/`, `.build/reorder-build.log`, `.build/package-1.3.5.log`, and `.build/tests/ui-run.Gk171C/`.

Artifact: `Paperpin-1.3.5-universal.dmg`, 2,082,459 bytes. SHA-256: `15ed7250114ddd7ccc689651bf59d4ae82f8f18fc674a501b92c1b975f110407`.

## Previous packaging validation — Paperpin 1.3.4

Packaging update validated on 12 November 2026 on Apple silicon, macOS 27.0.1. This build uses Xcode 27.2 / Swift 6.4.2, targets macOS 13+, and retains both Intel and Apple silicon executables. App features and the note-storage format are unchanged.

- All 43 storage, persistence, appearance, and login-policy checks passed with the selected toolchain.
- Release compilation passed with linker warnings treated as errors. Selecting the complete Xcode toolchain removes the prior Command Line Tools warning about an Intel compatibility archive. The system-wide developer selection was not changed.
- `package.zsh` built a fresh app, verified both architecture signatures, created and verified an HFS+ compressed DMG, mounted it read-only, copied out the app, and rechecked its signature, architectures, minimum OS setting, and executable bytes. The packaged app contains no quarantine attribute or personal notes.
- The Applications shortcut and first-open instructions are included. A separate check confirmed that packaging refuses to overwrite an existing installer. Shell syntax and Git whitespace checks passed.
- Artifact: `Paperpin-1.3.4-universal.dmg`, 2,721,226 bytes. SHA-256: `d558d4e5dc445846c2f8130ce31f8187a0f7aa4a677e7d5b6f49dcd46051a40a`.
- The installer is ad hoc signed, **not Apple-notarized**. This machine has no Developer ID signing identity, and the user chose the free distribution route. Recipients may need the normal Privacy & Security → Open Anyway approval. Share a browser download link rather than a chat attachment; a DMG cannot prevent a transfer app from adding restrictive metadata later.
- The user confirmed that 1.3.3 opens on an Intel Mac running macOS 15.7 after removing the transfer quarantine flag. This establishes the reported launch block's cause, not a full Intel feature test. A receiving-Mac download and first-open check of 1.3.4 remains necessary.
- A supplementary Intel QA run under Rosetta on the development Mac opened, edited, and saved notes, but its quick-panel-open assertion failed. It is not counted as a passing UI suite. The full UI suites, energy benchmarks, and older-OS runtime checks were not rerun for this packaging-only update.

Local evidence: `.build/package-1.3.4.log`, `.build/package-1.3.4-checks.log`, and `.build/distribution/`. A copy of the DMG and checksum is in Downloads. The installed app, personal notes, and login registration were not changed by this packaging work.

## Previous app validation — 1.3.3

Validated on 3 November 2026 on Apple silicon, macOS 27.0.1, using Swift 6.4 and the installed Command Line Tools. Branch: `codex/minimal-desktop-energy-glass`.

## Changes verified

- Liquid Glass now requires native macOS 26+ API support. Unsupported systems use opaque surfaces; View, board-layout, and quick-panel toggles are disabled and unchecked with an explanation. The old frosted-material fallback is removed. Supported Intel Macs are not excluded by architecture.
- An existing enabled glass preference cannot apply an unsupported effect and is retained for a future supported environment. All 32 native-support/preference/power/accessibility policy combinations were checked, along with guarded actions and preference preservation.
- Board and desktop checklists share their row and draft controls. Desktop checkboxes align with the first text line, including wrapped tasks. Task/body fonts, row spacing, hints, paper colors, and glass card surfaces match the board while retaining the compact desktop window.
- Removed the redundant whole-board Desktop Mode toggle from the View menu, board layout options, and quick panel. Minimal Mode remains the desktop-note experience; individual Show on desktop actions are unchanged.
- Removed the old board-pinning behavior and retired its saved preference. Migration from `DesktopMode=true` produces an ordinary board with working close/minimize controls. Floating and sidebar preferences survive mode changes and relaunch.
- Glass uses neutral pearl/slate surfaces, blue-violet controls, modern system typography, rounded cards, and subtle note-color accents. Light/dark board and desktop screenshots were visually inspected.
- The native desktop body editor measures wrapped text and grows/shrinks to fit. Empty bodies use a 38-point input with “Write a note…”; checklists begin directly below and use the remaining height.
- Long bodies are capped while remaining scrollable. Width changes reflow the editor without changing the saved window size.
- Keyboard focus, selection, undo, and saved content survive layout and appearance changes. Text deletion and undo recalculate height correctly.
- Existing autosave, Low Power Mode, accessibility fallbacks, desktop positioning, and launch settings remain in place. Height measurements are event-driven and deduplicated; no repeating measurement timer was introduced.

## Checks

| Suite | Passing checks |
| --- | ---: |
| Storage, persistence, appearance, login policy | 43 |
| Board, quick panel, keyboard, relaunch | 29 |
| Board layout, retired preference migration, and relaunch | 25 |
| Minimal windows and restoration | 33 |
| Content sizing, editing continuity, checklist consistency, glass visuals, relaunch | 25 |
| Simulated unavailable native glass, disabled menus, opaque rendering, editing, relaunch | 21 |

All 176 checks completed with zero failures. The universal arm64/x86_64 release build and strict ad hoc code-signature verification passed. The unavailable-native-glass suite uses a QA-only override on this Mac; that override is absent from the release executable. It verifies disabled controls, no native or frosted glass in board/desktop content, editing, saving, and relaunch with a saved enabled preference. Checklist comparisons verify native fonts, row spacing, and genuinely wrapped text. SwiftUI virtual checkbox frames were unavailable to the in-process test helper, so alignment was visually checked in paired screenshots rather than counted as an automated assertion.

Review screenshots using synthetic test notes are included in [docs/images](docs/images): [desktop paper](docs/images/desktop-paper.png), [desktop glass](docs/images/desktop-glass-dark.png), and [board glass](docs/images/board-glass-light.png).

Current local screenshots and logs: `.build/delivery-glass-availability/`. Earlier local screenshots remain in `.build/delivery-checklist-alignment/`, `.build/delivery-desktop-toggle/`, and `.build/delivery-polish/`. These `.build/` artifacts are ignored by Git and are not published.

## Installation and data

Paperpin 1.3.3 is installed at `/Applications/Paperpin.app`. The saved board's SHA-256 checksum is identical before and after the update and relaunch; no sample content was copied into it. Existing appearance and desktop selections were retained. A local rollback copy of 1.3.2, the board, and preferences is in `.build/pre-glass-availability/`.

## Performance and platform limits

This polish does not change the batching writer. Version 1.2's synthetic typing benchmark recorded 300 → 2 atomic writes, and its five-minute idle process measurements recorded zero writes in updated modes. Those earlier measurements were not rerun for this visual change and do not estimate battery life or separate WindowServer/GPU power. The original report is retained in `.build/pre-polish-update/VALIDATION-v1.2.md`.

Runtime testing used this Apple silicon Mac. Older macOS versions and Intel execution remain unverified. The installed command-line linker warns that its compatibility-packs archive lacks an Intel slice, although the universal app links and verifies successfully. No logout, forced sleep, or physical display disconnection was performed.
