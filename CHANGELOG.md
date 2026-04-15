# Changelog

All notable changes to QuickPad. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates are commit
dates; the app isn't versioned yet, so entries are grouped by ship date.

## [Unreleased]

### Added — Phase 7 (Activate the review loop)
- **Review mode** (**⌘R**). Card-by-card review of entries from
  exactly 7 / 30 / 90 days ago. Each card surfaces one entry and
  forces a real decision: Rescue (R), Graduate (G), Done/Cancel (C),
  or Skip (S / ↓). Esc exits. Closes the dormant "review" half of
  Karpathy's `append-and-review` loop — without it, the gravity
  system was just hiding old data, not surfacing it back.
- **Rescue counter** stored inline in the bracket token as `@rN`:
  `[task @r3] foo`. Missing `@rN` parses as 0, so existing streams
  remain forward-compatible. Every rescue increments the counter.
  In Review, entries with `@r3` or higher get a 🎓 hint suggesting
  Graduate.
- **Stale-task nudge**: pending `[task]` entries older than 7 days
  show a soft pulsing dot in the trailing label area. Tooltip:
  "Pending for N days — migrate or cancel?". Threshold sits well
  below the 30-day archive rule so stale tasks get noticed before
  they're auto-archived.
- **Stream stats strip** between header and input row:
  `today N · 7d N · ✓ N · ↑ N · stale N`. Shows what the stream
  currently looks like — closure rate, lifetime rescues, count of
  stale tasks waiting for triage. Hidden when the stream is empty
  or during search.

### Changed
- All bracket-token mutations (delete/undelete, task state change,
  bullet type change) route through a new `mutatingBracketToken`
  helper that splits off `@rN` first and reattaches it after, so
  the rescue counter survives every other operation.

### Added — Phase 6
- **Graduate to Pinned Note** (right-click entry → Graduate). Promotes
  a stream entry into its own `~/.quickpad/pinned/<slug>.md` file with
  a small frontmatter recording the original timestamp and bullet type,
  then removes the line from `stream.md`. Closes the
  `capture → review → rescue → graduate` loop that was missing — repeatedly
  rescued entries can now leave the stream when they've matured.
- **Pinned Notes submenu** under the menu bar's right-click menu —
  lists `~/.quickpad/pinned/*.md` (newest-modified first), opens with
  the system's default Markdown app. Includes a **Reveal Folder in
  Finder** entry.
- **Quick Capture mini panel** (⌥⇧N). Borderless `.nonactivatingPanel`
  centered at the top quarter of the active screen. Type, hit Enter,
  the panel dismisses and you stay in the app you came from. Replaces
  the previous behaviour where ⌥⇧N opened the full popover.
- **Hint bar** under the input row — clickable bullet chips
  (`[— note] [☐ task] [? question] [! idea]`) and prefix chips
  (`[r:] [w:] [l:] [*]`) that prepend the matching token into the draft.
  Toggle visibility from the header.
- **Archive search** — ⌘F now also searches every
  `~/.quickpad/archive/*.md` file. Hits appear in a read-only
  `── FROM ARCHIVE ──` section at the bottom of the result list.

### Changed — Phase 6
- Entries surfaced from the archive are read-only in the list — the
  context menu and click-to-rescue affordance are suppressed so a
  mutation can never target a file the row's section doesn't own.

## 2026-04-15 — Single theme, Auto appearance, chrome polish

### Changed
- Replaced the `event` bullet type with `question` (glyph: `?`). Questions
  fit a stream/append-and-review workflow better than events — for events
  people already have a calendar app; for open questions they had nothing.
  Tab cycle is now note → task → question → idea. Legacy `[event]` tokens
  in existing `stream.md` files still parse (and render as question), so
  no migration is required.
- Moved the unknown-bullet fallback glyph from `?` to `⋯` so it no longer
  collides with the new question glyph.
- Swept hardcoded `.white.opacity()` / `.secondary` / `.yellow` from the
  Island, edit field, and search highlight — everything now routes through
  theme tokens. InlineMarkdown code spans, links, and the search highlight
  pick up the theme accent.
- Unified trailing time labels to 24-hour `HH:mm` across the popover and
  Island (previously a mix of relative `2m`/`3h` and absolute `3pm`).
- Cached `Palette` in `ThemeManager` so SwiftUI body re-entry stops
  re-allocating `Color(red:)` tables per row.

### Added
- Option + left-click on the menu bar icon now opens the same context
  menu as right-click.

### Removed
- Multi-theme system. Shipped 10 presets (Dracula, Monokai, One Dark,
  Tokyo Night, Catppuccin, Gruvbox, etc.) and a Font Size submenu earlier
  the same day, then deleted both: without bundled fonts or syntax
  highlighting the non-default variants read worse than Default, and
  "which theme am I on" added cognitive load without delivering taste.
  `Palette` / `ThemeManager` are preserved as the home for any future
  single-axis adjustment. See `ROADMAP.md` → Not pursuing.

### Fixed
- Auto appearance was silently locked to Dark. `ThemeManager` now
  observes `NSApp.effectiveAppearance` via KVO and never passes `nil`
  to `preferredColorScheme`.

## 2026-04-13 — Island interaction & visual polish

### Added
- Bullet-type re-classification via right-click → Bullet Type submenu.
- Shortcut hints overlay (**⌘/**) listing every in-app shortcut.
- App icon assets (PNG, multiple sizes).

### Changed
- Centralized color palette, button styles, and fade dividers in
  `Views/Theme.swift`; all views read from it instead of hardcoded colors.
- Polished Island interaction: hover-driven compact ↔ expanded transition.

### Fixed
- Island panel click-through: events pass through transparent regions
  instead of blocking the app underneath.

## 2026-04-11 — Dynamic Island widget

### Added
- `IslandPanel` + `IslandView` — menu-bar-right-click → **Show Island**
  pins a Dynamic-Island-style pill at the top of the screen.
- Compact state shows the latest entry; hover expands to a taller panel.
- Unified SwiftUI spring animation (response 0.42, damping 0.8).

## 2026-04-11 — Rescue UX, export, CJK tuning

### Added
- Export visible entries as Markdown via **⌘E** (uses `NSSavePanel`).
- Undo for rescue (**⌘Z**) — file-snapshot restore.

### Changed
- Archive timer reduced from 1 hour to 24 hours (background interval).
  Note: the age threshold for archiving is still **30 days**.
- Text density tuning for mixed CJK/Latin content (line height, letter
  spacing).
- Rescue layout stabilized: list no longer jumps when an entry floats up.
- Age calculation uses calendar-day alignment (`startOfDay`) so entries
  flip from "today" → "yesterday" at local midnight.

## 2026-04-11 — Docs sync (README + roadmap)

Documentation-only pass reflecting Phase 2 and early Phase 3 work.

## 2026-04-10 — Phase 3 floating window + inline Markdown + auto-archive

### Added
- Detachable floating window (**⌘D**) with multi-display support, always
  on top (`NSPanel.level = .floating`).
- Auto-archive of done/cancelled tasks older than 30 days to
  `~/.quickpad/archive/YYYY-MM.md`.
- Inline Markdown rendering for stream entries (`` `code` ``, **bold**,
  `[link](url)`).

### Fixed
- New entries prepend at the top of the day (newest-first).

## 2026-04-10 — Phase 2: gravity + BuJo

### Added
- Opacity gravity-decay curve (6 levels from today → 30+ days).
- Day-separator label decay: TODAY → YESTERDAY → APR 6 · SUN → MAR 20.
- Hover-to-rescue: click an old entry to float it back to today.
- Task state toggle (click glyph: pending ↔ done; right-click: migrated
  / cancelled).
- Content prefixes (`read:`, `watch:`, `listen:`, `?`) render as tags.
- `*` priority marker → red left border.
- Type filter: **⌘1-4** by type, **⌘5** to clear.

## 2026-04-10 — Phase 1.5: edit + soft delete

### Added
- In-place edit (right-click → Edit) preserves the original timestamp.
- Soft delete (right-click → Delete) with a 5-second undo window
  (**⌘Z**); lines marked `[type>deleted]`, cleaned after 30 days.

## 2026-04-10 — Test coverage

### Added
- Unit tests for the pure-logic layer (parser, writer, mutator, archiver,
  exporter, inline markdown, gravity, task state, bullet type).
- Fixed 2 bugs caught by the new test suite.

## 2026-04-09 — Phase 1 MVP

Initial commit. Menu bar rapid logging:

- `NSStatusItem` + `NSPopover` menu bar presence.
- SwiftUI `LazyVStack` stream list.
- Input bar with bullet type cycling (note → task → event → idea) and
  Enter to append.
- `stream.md` read/write with day separators.
- Global hotkeys via Carbon: **⌥N** (toggle), **⌥⇧N** (quick append).
- FSEvents file watcher — vim and `echo >>` edits sync live.
- **⌘F** full-text search with match highlighting.
- Pin keeps the popover open.
