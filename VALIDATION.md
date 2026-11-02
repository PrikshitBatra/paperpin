# Validation — Paperpin 1.3.2

Validated on 3 November 2026 on Apple silicon, macOS 27.0.1, using Swift 6.4 and SDK 26.5. Branch: `codex/minimal-desktop-energy-glass`.

## Changes verified

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
| Storage, persistence, appearance, login policy | 40 |
| Board, quick panel, keyboard, relaunch | 29 |
| Board layout, retired preference migration, and relaunch | 25 |
| Minimal windows and restoration | 33 |
| Content sizing, editing continuity, checklist consistency, glass visuals, relaunch | 25 |

All 152 checks completed with zero failures. The universal arm64/x86_64 release build and strict ad hoc code-signature verification passed. Checklist comparisons verify native fonts, row spacing, and genuinely wrapped text. SwiftUI virtual checkbox frames were unavailable to the in-process accessibility helper on this OS, so checkbox alignment was verified in paired board/desktop screenshots rather than reported as an automated pass. Paper, light glass, and dark glass appearances were visually inspected.

Review screenshots using synthetic test notes are included in [docs/images](docs/images): [desktop paper](docs/images/desktop-paper.png), [desktop glass](docs/images/desktop-glass-dark.png), and [board glass](docs/images/board-glass-light.png).

Full local screenshots and logs: `.build/delivery-checklist-alignment/`. Earlier local screenshots remain in `.build/delivery-desktop-toggle/` and `.build/delivery-polish/`. These `.build/` artifacts are ignored by Git and are not part of the pull request.

## Installation and data

Paperpin 1.3.2 is installed at `/Applications/Paperpin.app` and running. The existing desktop note restored automatically. The saved board's SHA-256 checksum is identical before and after the update and relaunch; no sample content was copied into it. Existing appearance and desktop selections were retained. A local rollback copy of 1.3.1, the board, and preferences is in `.build/pre-checklist-alignment/`.

## Performance and platform limits

This polish does not change the batching writer. Version 1.2's synthetic typing benchmark recorded 300 → 2 atomic writes, and its five-minute idle process measurements recorded zero writes in updated modes. Those earlier measurements were not rerun for this visual change and do not estimate battery life or separate WindowServer/GPU power. The original report is retained in `.build/pre-polish-update/VALIDATION-v1.2.md`.

Runtime testing used this Apple silicon Mac. Older macOS versions and Intel execution remain unverified. The installed command-line linker warns that its compatibility-packs archive lacks an Intel slice, although the universal app links and verifies successfully. No logout, forced sleep, or physical display disconnection was performed.
