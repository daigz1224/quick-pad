# QuickPad

A macOS native menu bar app for rapid logging — fusing Karpathy's
append-and-review single stream, Bullet Journal symbols, and Raycast
Notes' floating menu-bar experience. See `docs/ARCHITECTURE.md` for the
full design.

## Status

**Phase 1 complete.** The app is usable end-to-end for append-and-review
workflows:

- Menu bar icon → popover with full stream rendering grouped by day
- Inline input bar (Enter to append, click the glyph to cycle bullet type)
- Global hotkeys: **⌥N** toggle popover, **⌥⇧N** open without ever closing
- Live sync: external edits to `~/.quickpad/stream.md` (vim, `echo >>`,
  etc.) reflect automatically via FSEvents
- **⌘F** in-popover search with live filtering and match highlighting
- Auto / Light / Dark appearance cycling, deep-dark background (#17171A)
- Pin button to keep the popover open while you work elsewhere

Phase 2 brings opacity gravity decay, click-to-rescue animation, and task
state toggling. Phase 3 graduates pinned notes to true floating windows.

## Build

Requires macOS 14, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen   # one-time, if needed
xcodegen generate       # produces QuickPad.xcodeproj
xcodebuild -project QuickPad.xcodeproj -scheme QuickPad -configuration Debug build
open build/Debug/QuickPad.app
```

Or open `QuickPad.xcodeproj` in Xcode and run.

`QuickPad.xcodeproj` is gitignored — regenerate it any time `project.yml`
changes.

## Tests

```sh
xcodebuild -project QuickPad.xcodeproj -scheme QuickPad \
  -configuration Debug test -destination 'platform=macOS'
```

Unit tests cover the pure-logic layer: `StreamParser`, `StreamWriter`
(including FS-integration via temp dirs), `BulletType`, and `TaskState`.
UI / hotkey / file-watcher layers are deliberately not unit-tested —
they depend on AppKit, Carbon, and FSEvents callbacks that are only
meaningfully exercised by running the app.

## Usage

Click the menu bar icon (three horizontal bullet lines) or press **⌥N**
anywhere to toggle the popover. The text field is focused automatically —
just start typing and hit Enter to append.

| Shortcut / click          | Action                                           |
|---------------------------|--------------------------------------------------|
| **⌥N**                    | Toggle popover (open ↔ close)                    |
| **⌥⇧N**                   | Open popover (never closes, safe to mash)        |
| **Enter** in input bar    | Append entry under today's date separator       |
| Click glyph in input bar  | Cycle bullet type: note → task → event → idea   |
| **⌘F**                    | Enter search mode (Esc to exit)                  |
| Click sun/moon icon       | Cycle Auto → Light → Dark                        |
| Click pin icon            | Keep popover open when focus leaves              |
| Right-click menu bar icon | Quit QuickPad                                    |

Content shortcut: typing `* foo` in the input bar writes `*priority foo`
to disk (matches the architecture doc's priority marker).

## Where the data lives

```
~/.quickpad/
└── stream.md          # append-only log, human-readable, vim-editable
```

If `stream.md` doesn't exist on first launch, the popover falls back to a
bundled sample fixture so the UI is never empty. QuickPad writes
atomically (temp file + rename) and never touches lines it didn't add,
so concurrent `vim` edits and QuickPad appends coexist safely.

## stream.md format

```
--- 2026-04-09 Thursday ---

- 2026-04-09T22:31+09:00 [idea] some insight
- 2026-04-09T20:15+09:00 [task] something to do
- 2026-04-09T18:00+09:00 [note] *priority read: paper title
- 2026-04-09T14:00+09:00 [event] meeting

--- 2026-04-08 Wednesday ---

- 2026-04-08T15:00+09:00 [task>migrated] punted to next week
- 2026-04-08T11:42+09:00 [task>done] shipped a thing
```

Bullet types: `note`, `task`, `event`, `idea`. Task states: `task>done`,
`task>migrated`, `task>cancelled`. Content prefixes `read:`, `watch:`,
`listen:`, leading `?` are hoisted into a small tag column. Lines that
don't match the format are kept verbatim instead of being dropped, so
round-trips never lose data.
