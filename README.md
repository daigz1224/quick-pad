# QuickPad

A macOS 14+ menu bar app for rapid logging — fusing Karpathy's
append-and-review single stream, Bullet Journal rapid logging symbols,
and Raycast Notes' floating menu-bar experience.

See `docs/ARCHITECTURE.md` for the full design rationale, `CHANGELOG.md` for
recent changes, and `ROADMAP.md` for plans.

## Features

- **Menu bar popover** — click the icon or press **⌥N** anywhere to toggle
- **Quick Capture panel** — press **⌥⇧N** anywhere to summon a borderless mini input at the top of the active screen; type, hit Enter, the panel closes and you're back in your original app
- **Dynamic Island widget** — right-click the menu bar icon to toggle the always-visible pill that shows the latest entry; hover to expand, click to dismiss
- **Floating window** — detach with **⌘D** for always-on-top note taking
- **Rapid input** — Enter to append, Tab to cycle bullet type (note → task → question → idea)
- **Hint bar** — clickable bullet/prefix chips below the input row for one-click type switching and `read:` / `watch:` / `listen:` / `*priority` insertion; toggle on/off from the header
- **Gravity decay** — older entries fade in opacity; day separators decay from "TODAY" → "YESTERDAY" → "APR 6 · SUN" → "MAR 20"
- **Rescue** — hover old entries and click to float them back to today; undo with **⌘Z**
- **Task state** — click task glyph to toggle done/pending; right-click for migrated/cancelled
- **Change bullet type** — right-click → Bullet Type to re-classify an existing entry
- **In-place edit** — right-click → Edit to fix typos without breaking timestamp
- **Soft delete + undo** — right-click → Delete with 5-second undo window
- **Graduate to pinned note** — right-click → Graduate writes the entry to `~/.quickpad/pinned/<slug>.md` and pulls it out of the stream; pinned notes appear under the popover header's **⋯** menu
- **Inline Markdown** — `` `code` ``, **bold**, `[links](url)` render natively
- **Search** — **⌘F** full-text search across the live stream *and* every `~/.quickpad/archive/*.md` file; archive hits appear under a `── FROM ARCHIVE ──` divider
- **Review mode** — **⌘R** opens a card-by-card review of entries from 7 / 30 / 90 days ago; each card offers Rescue · Graduate · Done/Cancel · Skip with single-key shortcuts. Closes Karpathy's review loop without inviting list-skim
- **Rescue counter** — every rescue bumps `@rN` inside the bracket token; entries rescued ≥3 times get a 🎓 hint in Review suggesting Graduate
- **Stale-task nudge** — pending tasks older than 7 days get a soft pulsing dot in the trailing label (tooltip: "Pending for N days — migrate or cancel?")
- **Stats strip** — between header and input: `today N · 7d N · ✓ N · ↑ N · stale N` so you can see the stream's current shape at a glance
- **Type filter** — **⌘1-4** to filter by note/task/question/idea, **⌘5** to clear
- **Export** — **⌘E** exports visible entries as Markdown via save dialog
- **Shortcut hints** — **⌘/** toggles an overlay listing every shortcut
- **Auto-archive** — done/cancelled tasks older than 30 days move to `~/.quickpad/archive/YYYY-MM.md`
- **Live sync** — external edits (vim, `echo >>`) reflect automatically via FSEvents
- **Appearance** — Auto / Light / Dark cycling (menu bar right-click → Appearance)
- **Pin** — keep popover open while working elsewhere
- **Polished visuals** — themed inline Markdown (code/links pick up the
  accent), accent-tinted timestamps, fade dividers, CJK/Latin density
  tuning

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
| **⌥⇧N** | Quick Capture mini panel (system-wide) |
| **Enter** | Append entry |
| **Tab** | Cycle bullet type |
| **⌘F** | Search (stream + archive) |
| **⌘R** | Review mode (cards) |
| **⌘D** | Detach / reattach floating window |
| **⌘E** | Export visible entries as Markdown |
| **⌘Z** | Undo delete or rescue |
| **⌘1-4** | Filter by type (note/task/question/idea) |
| **⌘5** | Clear filter |
| **⌘/** | Toggle shortcut hints overlay |
| **Right-click entry** | Edit, Delete, Rescue, Graduate, change task state, change Bullet Type |
| **Click task glyph** | Toggle pending ↔ done |
| **Hover old entry** | Shows "↑ rescue" hint (click to rescue) |
| **⌘Q** | Quit (also under the popover ⋯ menu) |
| **Right-click menu bar icon** | Toggle Dynamic Island |
| **Popover header ⋯** | Pinned Notes, Quit |

Content shortcut: typing `* foo` writes `*priority foo` (red left border).

## Data

```
~/.quickpad/
├── stream.md              # main stream (newest day first)
├── pinned/                # graduated entries — one Markdown file per note
│   └── onboarding-doc-draft.md
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
- 2026-04-10T14:00:00+08:00 [question] why is p99 flat after the cache warm-up?
- 2026-04-10T10:00:00+08:00 [idea] cool idea
```

- **Bullet types**: `note`, `task`, `question`, `idea` (the legacy `event` token still parses as `question`)
- **Task states**: `task>done`, `task>migrated`, `task>cancelled`
- **Rescue count**: `[task @r3]` means rescued back to today 3 times; missing `@rN` parses as 0
- **Soft delete**: `[note>deleted]` — hidden from UI, cleaned after 30 days
- **Ordering**: newest day at top, newest entry first within each day
- **Content prefixes**: `read:`, `watch:`, `listen:`, `?` are shown as tags
- Malformed lines are preserved verbatim (never dropped)

## Tests

```sh
xcodebuild test -project QuickPad.xcodeproj -scheme QuickPad \
  -configuration Debug -destination 'platform=macOS'
```

168 tests across 11 suites covering parser, writer, mutator, archiver,
exporter, inline markdown, gravity decay, task state, bullet type,
pinned-note slug + graduation logic, and the `@rN` rescue-count
schema.
