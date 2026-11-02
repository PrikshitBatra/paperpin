# Paperpin

Paperpin is a native sticky-note board for macOS. Keep multiple notes in view, mix freeform text with checklists, and check off tasks to move them to the archive. Restore a task to put it back on its original sticky.

The menu bar shows the pending count and can also show the next task’s title. Click the icon or press **Control–Option–Space** to add or complete tasks without opening the board. Notes and unfinished drafts save automatically on your Mac.

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

Use a Mac with Swift and a macOS 26+ SDK. The build script creates a universal app for Apple silicon and Intel Macs running macOS 13 or later. It probes SwiftUI compiler support and can fall back to an installed macOS 26 SDK if a newer Command Line Tools SDK lacks the required macro plugin. Set `PAPERPIN_SDKROOT` to select a specific working SDK.

```sh
./build.zsh
open .build/Paperpin.app
```

You can copy the built app into Applications. Your board remains at `~/Library/Application Support/Paperpin/Board.json`, using the original version-1 format. Desktop window geometry and appearance preferences live separately in UserDefaults.

For a first local installation, launch the installed app with `--setup-desktop --enable-login-item` to select minimal mode and request login registration. The setup flag applies once and never overrides a later mode choice. Login registration reports its actual result; macOS may require user approval.

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
```

The layout suite checks normal board controls, floating, sidebar, minimize/reopen behavior, preference restoration, and migration away from the retired whole-board desktop setting. The minimal-mode suite checks native editing, shared notes, window restoration, fullscreen transitions, simulated display removal, and lifecycle saves. Screenshots and logs are written under `.build/tests/`.

The glass-unavailable suite simulates absent native support in the isolated QA app, checking disabled controls, opaque rendering, and preserved notes/preferences across relaunch. The simulation override is excluded from release builds.

`Tools/TypingBenchmark.swift` compares atomic save counts against the historical store (compile the historical version with `-D PAPERPIN_BASELINE`). `Tools/measure-idle.py PID --output result.json` measures five minutes of process CPU, wakeups, memory, and disk counters after a 30-second warmup. These process counters do not isolate WindowServer/GPU energy or predict battery life.
