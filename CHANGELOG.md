# Changelog

All notable changes to QuickPad. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates are commit
dates; the app isn't versioned yet, so entries are grouped by ship date.

## [Unreleased]

### Changed
- Replaced the `event` bullet type with `question` (glyph: `?`). Questions
  fit a stream/append-and-review workflow better than events — for events
  people already have a calendar app; for open questions they had nothing.
  Tab cycle is now note → task → question → idea. Legacy `[event]` tokens
  in existing `stream.md` files still parse (and render as question), so
  no migration is required.
- Moved the unknown-bullet fallback glyph from `?` to `⋯` so it no longer
  collides with the new question glyph.

### Added
- Option + left-click on the menu bar icon now opens the same context
  menu as right-click.
- Font Size submenu (Small / Medium / Large / Extra Large). Choice
  persists across launches and scales every themed text surface.
- Six more built-in themes popular in the VSCode and Obsidian communities:
  **Dracula**, **Monokai**, **One Dark**, **Tokyo Night**, **Catppuccin**,
  and **Gruvbox** — bringing the total to 10. Each theme now drives
  typography too (font family, weight, italic, tracking), not just color.
  Access via menu bar right-click → Theme.

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
