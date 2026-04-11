# QuickPad

A macOS 14+ menu bar app for rapid logging — fusing Karpathy's
append-and-review single stream, Bullet Journal rapid logging symbols,
and Raycast Notes' floating menu-bar experience.

See `docs/ARCHITECTURE.md` for the full design rationale.

## Features

- **Menu bar popover** — click the icon or press **⌥N** anywhere to toggle
- **Floating window** — detach with **⌘D** for always-on-top note taking
- **Rapid input** — Enter to append, Tab to cycle bullet type (note → task → event → idea)
- **Gravity decay** — older entries fade in opacity; day separators decay from "TODAY" → "YESTERDAY" → "APR 6 · SUN" → "MAR 20"
- **Rescue** — hover old entries and click to float them back to today; undo with **⌘Z**
- **Task state** — click task glyph to toggle done/pending; right-click for migrated/cancelled
- **In-place edit** — right-click → Edit to fix typos without breaking timestamp
- **Soft delete + undo** — right-click → Delete with 5-second undo window
- **Inline Markdown** — `` `code` ``, **bold**, `[links](url)` render natively
- **Search** — **⌘F** full-text search with match highlighting
- **Type filter** — **⌘1-4** to filter by note/task/event/idea, **⌘5** to clear
- **Export** — **⌘E** exports visible entries as Markdown via save dialog
- **Auto-archive** — done/cancelled tasks older than 30 days move to `~/.quickpad/archive/YYYY-MM.md`
- **Live sync** — external edits (vim, `echo >>`) reflect automatically via FSEvents
- **Appearance** — Auto / Light / Dark cycling
- **Pin** — keep popover open while working elsewhere

## Install

### From source

Requires macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen          # one-time
git clone <repo-url> && cd quick-pad
xcodegen generate
xcodebuild -project QuickPad.xcodeproj -scheme QuickPad -configuration Release build
```

The built app is at `~/Library/Developer/Xcode/DerivedData/QuickPad-*/Build/Products/Release/QuickPad.app`.

### From zip (shared by someone)

1. Unzip `QuickPad.zip`
2. Drag `QuickPad.app` to `/Applications`
3. First launch: right-click → Open → confirm (only needed once)

## Usage

| Shortcut | Action |
|---|---|
| **⌥N** | Toggle popover (system-wide) |
| **⌥⇧N** | Open popover, never closes (system-wide) |
| **Enter** | Append entry |
| **Tab** | Cycle bullet type |
| **⌘F** | Search |
| **⌘D** | Detach / reattach floating window |
| **⌘E** | Export visible entries as Markdown |
| **⌘Z** | Undo delete or rescue |
| **⌘1-4** | Filter by type (note/task/event/idea) |
| **⌘5** | Clear filter |
| **Right-click entry** | Edit, Delete, Rescue, change task state |
| **Click task glyph** | Toggle pending ↔ done |
| **Hover old entry** | Shows "↑ rescue" hint (click to rescue) |

Content shortcut: typing `* foo` writes `*priority foo` (red left border).

## Data

```
~/.quickpad/
├── stream.md              # main stream (newest day first)
└── archive/               # auto-archived done/cancelled tasks
    └── 2026-04.md
```

If `stream.md` doesn't exist on first launch, a bundled sample is shown.

QuickPad writes atomically (temp file + rename) and coexists safely with
concurrent vim edits.

## stream.md format

```markdown
--- 2026-04-11 Saturday ---

- 2026-04-11T10:30:00+08:00 [note] some insight
- 2026-04-11T09:00:00+08:00 [task] something to do

--- 2026-04-10 Friday ---

- 2026-04-10T22:00:00+08:00 [task>done] shipped a thing
- 2026-04-10T15:00:00+08:00 [task>migrated] punted to next week
- 2026-04-10T14:00:00+08:00 [event] architecture review meeting
- 2026-04-10T10:00:00+08:00 [idea] cool idea
```

- **Bullet types**: `note`, `task`, `event`, `idea`
- **Task states**: `task>done`, `task>migrated`, `task>cancelled`
- **Soft delete**: `[note>deleted]` — hidden from UI, cleaned after 30 days
- **Ordering**: newest day at top, newest entry first within each day
- **Content prefixes**: `read:`, `watch:`, `listen:`, `?` are shown as tags
- Malformed lines are preserved verbatim (never dropped)

## Tests

```sh
xcodebuild test -project QuickPad.xcodeproj -scheme QuickPad \
  -configuration Debug -destination 'platform=macOS'
```

133 tests across 9 suites covering parser, writer, mutator, archiver,
exporter, inline markdown, gravity decay, task state, and bullet type logic.
