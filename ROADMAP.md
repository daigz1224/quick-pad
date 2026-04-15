# Roadmap

Short list of what's shipped, what's being considered, and what's out of
scope. See `docs/ARCHITECTURE.md` for the design philosophy and
`CHANGELOG.md` for ship dates.

## Shipped

- **Phase 1 — MVP** · menu bar popover, stream input, global hotkeys,
  FSEvents sync, ⌘F search, pin.
- **Phase 1.5 — Edit & soft delete** · right-click edit (preserves
  timestamp), soft delete with ⌘Z undo.
- **Phase 2 — Gravity & BuJo** · opacity decay, day-separator decay,
  rescue, task state, content prefixes, priority marker, ⌘1-5 filter.
- **Phase 3 — Floating window** · ⌘D detach, multi-display, inline
  Markdown, auto-archive, newest-first.
- **Phase 4 — Polish** · export (⌘E), rescue undo, themed inline
  Markdown, shortcut hints (⌘/), bullet-type re-classification,
  CJK/Latin tuning.
- **Phase 5 — Dynamic Island** · always-visible pill, compact/expanded
  states, click-through.
- **Phase 6 — Loop closure** · Graduate to Pinned Notes (right-click →
  Graduate, surfaced in the menu bar's Pinned Notes submenu), Quick
  Capture mini panel (⌥⇧N), hint bar with bullet/prefix chips, archive
  search.
- **Phase 7 — Activate the review loop** · Review mode (⌘R) with
  card-by-card 7/30/90-day buckets and single-key Rescue/Graduate/
  Done/Skip; rescue counter stored inline as `@rN`; stale-task pulse
  (≥7 day pending tasks); stream stats strip showing today / 7d /
  closure / rescues / stale at a glance.

## Considering

Ideas that were initially scoped out but may resurface if demand or
personal pain warrants them:

- **`⌘⇧G` keyboard shortcut for Graduate** — currently right-click only
  because there's no row-selection focus model in the popover yet.
- **Merge entries (⌘M)** — combine selected entries during review.
- **`~/.quickpad/config.toml`** — user-configurable hotkeys, gravity
  curve, archive threshold, font, review thresholds. Currently all
  values are hardcoded.
- **Multi-display refinements for Island** — smarter placement when the
  active screen changes mid-session.
- **Per-entry customisable archive threshold** — today it's a single
  30-day rule across all done/cancelled tasks.
- **Auto-graduate suggestion in the stream view** — Phase 7 surfaces
  the 🎓 hint inside Review mode; could also pop up inline on a row
  when its `@rN` crosses a threshold without waiting for review.

## Not pursuing

Tried and explicitly removed:

- **Multiple theme presets / Obsidian-Dracula-style theming.** Shipped
  10 presets in 2026-04-15, deleted them the same day. The non-default
  variants all read worse than Default — borrowed-name aesthetics
  without bundled fonts or syntax highlighting felt like recolored
  defaults, and "which theme am I on" added cognitive load without
  delivering taste. Single polished Default beats a menu of half-built
  variants. Architecture (Palette/ThemeManager) preserved as the home
  for any future single-axis improvement (e.g., one carefully designed
  alternate); never reopen as "10 themes" again.

## Not planned

Deliberately out of scope — say no to stay KISS:

- Folders, nested categories, or hierarchical tags.
- Cloud sync (the file is plain Markdown in `~/.quickpad/`; bring your
  own sync via iCloud Drive, Syncthing, git, rsync, etc.).
- Mobile apps.
- Full WYSIWYG Markdown editor — inline rendering only, no toolbar.
- Collaboration / multi-user editing.
