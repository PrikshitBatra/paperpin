# Paperpin

Paperpin is a native sticky-note board for macOS. Keep multiple notes in view, mix freeform text with checklists, and check off tasks to move them to the archive. Restore a task to put it back on its original sticky.

The menu bar shows the pending count and can also show the next task’s title. Click the icon or press **Control–Option–Space** to add or complete tasks without opening the board. Notes and unfinished drafts save automatically on your Mac.

## Desktop mode

Choose **View → Desktop Mode** to keep the board on the desktop behind other windows. Choose **Open board** in the menu bar panel when you want to edit it in front of another app. Switching apps puts it back on the desktop.

Press **Control–Command–S** to hide or show the sidebar. Both layout settings are also available in the menu bar panel’s **•••** menu.

## Build and run

Use a Mac with the macOS SDK and Swift 5.10 or newer. The build script creates a universal app for Apple silicon and Intel Macs running macOS 13 or later.

```sh
./build.zsh
open .build/Paperpin.app
```

You can copy the built app into Applications. Your board is stored at `~/Library/Application Support/Paperpin/Board.json`.

## Tests

Run the storage checks from the repository root.

```sh
mkdir -p .build/tests
xcrun swiftc Sources/BoardStore.swift Tests/StoreChecks.swift -o .build/tests/store-checks
.build/tests/store-checks .build/tests
```

The UI checks use a separate test app and temporary board. Quit Paperpin before running the keyboard-shortcut checks so the test app can register the shortcut.

```sh
./Tests/run-ui.zsh
PAPERPIN_CHECK_LAYOUT=1 ./Tests/run-ui.zsh
```
