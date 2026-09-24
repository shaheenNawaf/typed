# Today view presents as "Today" in the workspace chrome

Written against: `0e33c367c14fd99e3045396d096467a77d638211` (`lib/` is clean at this commit; `BRANDING.md` and `README.md` carry unrelated uncommitted wording edits).

## Evidence chain

- Surface: Home screen → "TODAY" overview card → the filtered note list it opens (desktop breadcrumb, mobile header title, mobile editor back button)
- Problem: Tapping the TODAY card runs `_setFilter('today')`, but every piece of navigation chrome that renders the active filter's name treats `today` as its fallback value `'Notes'`. The user taps a card labeled TODAY and lands on a screen titled "Notes", with no sidebar item highlighted. The view's own empty state says "Nothing today", so the content and the chrome contradict each other within the same task.
- Design evidence:
  - `lib/screens/home_screen.dart:2699` — the TODAY card's `onTap: () => _setFilter('today')` (the only navigation entry point to this filter).
  - `lib/screens/home_screen.dart:1590-1609` — `_workspaceSectionLabel` has cases for finance/tasks/meeting/journal/archive/trash/home and returns `'Notes'` for everything else; `today` falls through.
  - `lib/screens/home_screen.dart:2064-2076` — `_backTargetLabel` (the mobile editor's back button label) maps notes/home/finance/tasks/archive/trash/pinned but not `today`, so it also reads "Notes" while navigating back to a Today list.
  - `lib/widgets/note_list.dart:538-543` — the `today` filter's empty state ("Nothing today / Notes you edit today will appear here") proves the view is meant to present as Today.
  - `lib/widgets/workspace_header.dart:103-137` — renders `sectionLabel` as the mobile title and as the desktop breadcrumb crumb; it has no label logic of its own.
  - Same root, same fix, reachable today: `lib/widgets/sidebar.dart:324` navigates to the `pinned` filter, which also falls through to `'Notes'` in `_workspaceSectionLabel`, while `_backTargetLabel` already maps `pinned` → `'Pinned'` and the sidebar section is titled "Pinned". The in-repo vocabulary for that filter is established.
- Owner: `lib/screens/home_screen.dart` (both label getters live on `_HomeScreenState`)
- Scope and affected surfaces: desktop `WorkspaceHeader` breadcrumb; mobile workspace header title; mobile full-screen editor back button — all consumers of `_workspaceSectionLabel` and `_backTargetLabel`
- Uncertainty: none material. The correct value is determined by existing in-repo vocabulary (`note_list.dart:598` dates the section "Today"; the card is "TODAY"; the sidebar section is "Pinned").

## Design decision

Complete the two label mappings so every filter the shell itself can navigate to resolves to its real name, instead of being swallowed by the `'Notes'` default:

- `_workspaceSectionLabel`: add `case 'today': return 'Today';` and `case 'pinned': return 'Pinned';`
- `_backTargetLabel`: add `'today': 'Today',` to the constant map (`'pinned'` is already present).

This resolves the root problem — an incomplete enumeration — rather than special-casing one call site. No other widget changes; the header and back button render whatever these getters return.

## Reuse

- Existing label getters `_workspaceSectionLabel` and `_backTargetLabel` on `_HomeScreenState` — no new primitives, strings, or widgets.
- Existing vocabulary: `'Today'` (already used by `_dateSection` in `lib/widgets/note_list.dart:598` and by the card title), `'Pinned'` (already used by the sidebar section label and `_backTargetLabel`).
- Exemplar: the existing `case 'archive': return 'Library / Archive';` entry in the same switch shows the intended pattern for shell-navigable filters.

No new primitive is required; the existing system fully expresses the decision.

## Changes

1. `lib/screens/home_screen.dart` — `_workspaceSectionLabel` (lines 1590-1609)
   - Change: insert `case 'today': return 'Today';` and `case 'pinned': return 'Pinned';` before the `default:` branch. Keep all existing cases and the `default: return 'Notes';` fallback (it remains correct for the `notes` filter).
   - Preserve: every existing case's return value; the getter's signature and purity.
   - Verify: with `_activeFilter == 'today'` the getter returns `'Today'`; with `'pinned'` it returns `'Pinned'`; with `'notes'` it still returns `'Notes'`.

2. `lib/screens/home_screen.dart` — `_backTargetLabel` (lines 2064-2076)
   - Change: add `'today': 'Today',` as an entry in the constant map.
   - Preserve: the `_activeTag != null` early return (`'Notes'`), all existing entries, the `'Notes'` fallback.
   - Verify: on mobile, opening the editor from the Today list shows a back button labeled "Today".

## Scope

- Inherit: desktop `WorkspaceHeader` breadcrumb (`_buildWorkspaceHeader` → `WorkspaceHeader.sectionLabel`), mobile workspace header title, mobile editor back button (`_buildEditorFullScreen`) — all render these getters' output and change automatically.
- Verify: finance, tasks, meetings, journal, archive, trash, home, and notes views still show exactly their previous labels; the tag-chip flow (`_onTagFilter` sets `_activeFilter = 'notes'`) is untouched.
- Exclude: the `untagged` filter (no navigation entry point exists in the app — do not add a label for dead code); sidebar active-state highlighting for `today` (the sidebar has no Today item by design; out of scope); the pre-existing label asymmetry where `_backTargetLabel` says "Archive" but `_workspaceSectionLabel` says "Library / Archive" (both are evidence-based for their contexts; do not unify here); mobile bottom-nav highlighting, which stays on "Notes" for the `today` filter (a separate mapping concern, unchanged).

## Validation

- Product: Launch the app → Home → tap the TODAY overview card → the list's header reads "Today" (desktop breadcrumb "Workspace › Today"; mobile title "Today"); open a note from that list on mobile → back button reads "Today" and returns to the Today list; tap a pinned note in the sidebar on desktop → breadcrumb reads "Pinned".
- Interface: light and dark mode; narrow (<1024 px) and wide viewports; the empty extreme (nothing edited today → "Nothing today" empty state beneath a "Today" header); a populated extreme (several notes edited today → "Today"-headed list with rows).
- System: `grep -n "'Today'" lib/` shows the label coming from the same vocabulary as `note_list.dart`'s section header — no parallel naming introduced; no new widgets or strings.
- Repository: `flutter analyze` → `No issues found!`; `flutter test` → all existing tests pass (none cover these getters; run confirms no regression).

## Stop conditions

- Stop if `_workspaceSectionLabel` or `_backTargetLabel` gains a new consumer that relies on the `'Notes'` default for `today`/`pinned` (re-check every call site before editing).
- Stop if the intended design is instead that `today` is a sub-view of Notes — in that case the defect is the TODAY card's navigation target, and this plan should be discarded for a different change.
- Stop if the sidebar gains a Today/Pinned nav item during this work; active-state handling then belongs in this plan and the scope must widen.

## Design documentation

- None. No documented design rule changes; the code is being completed to match the app's own established vocabulary.
