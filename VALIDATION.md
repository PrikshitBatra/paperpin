# Validation — Paperpin 1.3.4

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
