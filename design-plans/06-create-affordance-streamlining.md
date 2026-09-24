# 06 — Create-affordance streamlining

**Problem.** Mobile screens stack up to three simultaneous "+" buttons that do the same thing. The Notes/Tasks tabs render a header "+" icon, a floating action button, and the dock's Create button — all three open the identical template picker. Finance renders a quick-add FAB next to the dock Create button. Home renders a Create square in the greeting header, a "New page" row, and the dock button. The dock (MobileNav) is always visible on mobile, which makes every page-level "+" redundant chrome — and the FABs occlude content (known finance friction #28: FAB covers the 3rd category amount).

## Evidence chain

| # | Evidence | Source |
|---|----------|--------|
| E1 | Mobile Notes tab renders 3 create buttons at once: header "New note" (e343), unlabeled newNoteFab (e352), dock "Create" (e341) — all fire `_openTemplatePicker` | Playwright semantics 390×844, this build; note_list.dart:207-223, :275-309; home_screen.dart:2216, :2372 |
| E2 | Mobile Finance tab renders 2: quickAddFab (e336 → expense/income sheet) + dock Create (e341 → template picker) | Playwright semantics; note_list.dart:193-206, :114-143 |
| E3 | Mobile Home renders 3: Create square 36px accent (`_buildHomeIntro`) + "New page" quiet row (`_createNote`, direct blank) + dock Create | home_screen.dart:2540-2556, :2680-2685; mobile_nav.dart:99-135 |
| E4 | Tasks tab = Notes tab (same NoteList, same FAB + header icon + dock) | home_screen.dart:2406-2412 (`_buildNoteListMobile`) |
| E5 | Desktop 1440×900 finance: "+ Add transaction" header button NOT rendered (pane 338px < 380px threshold); it appears only at ≥ ~1580px windows, duplicating the FinanceWorkspace Expense/Income buttons shipped in slice A | Playwright find: no match at 1440; note_list.dart:310-345 (`!isMobile` pane gate) |
| E6 | Desktop narrow column (notes/tasks) shows a small "+" icon in the header — the only list-level create affordance (no dock on desktop) | note_list.dart:286-290 (pane-isMobile icon variant) |
| E7 | Onboarding guide "Tracking Finance" instructs: "Open Finance and choose **Add transaction**…" — will reference a removed button | onboarding.dart:120; asserted in utils_test.dart:127 |
| E8 | The finance FAB's 1-tap expense log is the most frequent finance action; dock Create currently opens the 7-option picker where Quick expense/income are buried | note_list.dart:199; QA image 08 (picker = 7 options) |

## Design decisions

- **D1 — One chrome "+" per surface.** Mobile: the dock Create button is the only chrome create affordance. Desktop (no dock): keep exactly one page-level button per page (header "+ New", Home Create square, workspace Expense/Income).
- **D2 — Context-aware dock.** On the Finance tab the dock Create opens the Add expense / Add income sheet (preserves 1-tap logging, E8); on every other tab it opens the template picker (unchanged). The sheet implementation moves from note_list (dead after FAB removal) into home_screen.
- **D3 — Window-based gates, not pane-based.** The header "New note" button and Home Create square hide only in the mobile shell (window < 1024px). The desktop narrow column (338px pane) keeps its "+" — gating on pane width would strip desktop's only affordance (E6, failure mode 2).
- **D4 — Content-level affordances stay.** "New page" quiet row (Home), empty-state CTAs ("Create Note", "Add First Transaction"), editor "+ Entry", "Add budget", command palette, Ctrl+N. These are contextual actions inside content, not competing chrome.
- **D5 — Desktop finance header button goes.** "+ Add transaction" (≥1580px only) duplicates the workspace Expense/Income buttons; when a note is open the editor's "+ Entry" covers entry add. Trade-off: quick-add to *today's* note while a note is open on a huge desktop loses its shortcut — accepted (niche; command palette remains).
- **D6 — Guide text coherence.** Update the "Tracking Finance" onboarding copy to the new flow and its utils_test assertion in the same change (E7).

## Changes

1. `lib/widgets/note_list.dart` — delete quickAddFab (:193-206) and newNoteFab (:207-223) blocks; unwrap the now-single-child Stack; delete `_showFinanceActions` (:114-143); gate the header "New note" block (:275-309) on window-isDesktop; delete the desktop "+ Add transaction" block (:310-346). Props `onQuickAddEntry`/`onQuickAddIncome` stay (empty-state CTA :552 uses them).
2. `lib/screens/home_screen.dart` — add `_showFinanceQuickSheet()` (moved 2-choice sheet calling `_quickAddEntry`/`_quickAddIncome`) + `_onDockCreate()` (`_currentTab == 'finance' ? sheet : _openTemplatePicker`); wire MobileNav `onCreate: _onDockCreate` (:2216); gate the `_buildHomeIntro` Create square + its spacer (:2539-2556) on isDesktop.
3. `lib/utils/onboarding.dart` + `test/utils_test.dart` — new guide line describing dock Create (mobile) / Expense-Income buttons (desktop); test assertion updated to a stable phrase from the new text.
4. `test/create_affordance_test.dart` (new) — widget tests: mobile-width NoteList renders no FAB & no header New; desktop-width NoteList renders header New; dock handler routing (finance → sheet, notes → picker) via HomeScreen or extracted handler test.

## Validation

- `flutter analyze --no-pub` clean; `flutter test` all green (71 existing + new).
- Playwright semantics at 390×844: Notes/Tasks/Home/Finance each show exactly one chrome create button; dock on Finance opens expense/income sheet; "Add expense" reaches EntrySheet.
- Playwright at 1440×900: Notes narrow column still has header "+"; Home still has Create square; Finance workspace unchanged.
- Screenshots → image-analyzer for layout verdicts (no orphaned spacing where FABs/buttons were removed).
