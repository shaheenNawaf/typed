# Home screen honors the one-accent-CTA discipline

Written against: `0e33c367c14fd99e3045396d096467a77d638211` (`lib/` is clean at this commit). The working tree carries an uncommitted `BRANDING.md` wording edit ("crossbar" → "period"); the accent-discipline sentence this plan relies on is identical in the committed version apart from that word.

## Evidence chain

- Surface: Home screen (the `_activeFilter == 'home'` view), rendered on both desktop (inside `_buildDesktop`) and mobile (`_buildMobileContent` → `_buildHomeScreen`). Two sections are on screen simultaneously: the greeting row and the QUICK ACTIONS row.
- Problem: The Home screen renders two accent-filled CTAs that perform the identical action. The "New note" `FilledButton.icon` in the greeting row and the "Note" pill in the Quick Actions row both render with `context.colors.accent` as their background and both invoke `_createNote`. This violates the brand system's documented accent discipline.
- Design evidence:
  - `BRANDING.md` §3 (Color palette): "**Accent discipline:** Max 2 visible uses of accent per screen. The `y` in the wordmark, the period in the mark, selected note card border, one CTA at a time. That's it." — a committed, current design decision governing accent usage per screen.
  - `lib/screens/home_screen.dart:2338-2347` — `_buildHomeIntro` renders `FilledButton.icon(... 'New note')` with `backgroundColor: context.colors.accent`, `foregroundColor: context.colors.onAccent`, `onPressed: _createNote`.
  - `lib/screens/home_screen.dart:2596-2628` — the private `pill()` helper inside `_buildQuickActions`: `color: accent ? c.accent : c.surface`, `border: accent ? null : Border.all(color: c.border)`, icon `accent ? c.onAccent : c.muted`, text `accent ? c.onAccent : c.fg`.
  - `lib/screens/home_screen.dart:2637-2643` — the only call site that passes `accent: true`: `pill(label: 'Note', icon: Icons.add, accent: true, onTap: _createNote)`.
  - Exemplar for the corrected state: the five sibling pills (`Expense`, `Income`, `Task`, `Meeting`, `Journal`, lines 2644-2649) already render the non-accent treatment; the "New note" FilledButton is the canonical single CTA (same treatment as onboarding's "Get started" button, `lib/screens/onboarding_screen.dart:460-465`).
- Owner: `lib/screens/home_screen.dart` (`pill()` and its call sites are private to `_buildQuickActions`)
- Scope and affected surfaces: the Quick Actions row of the Home screen on desktop and mobile
- Uncertainty: none. The rule, both render paths, and the corrected variant all exist in the repo; no value must be invented.

## Design decision

Demote the "Note" quick-action pill to the standard surface pill treatment, leaving "New note" as the screen's single accent CTA. Both controls perform `_createNote`; keeping the accent on the FilledButton (the canonical CTA exemplar) and matching the pill to its siblings resolves the documented "one CTA at a time" violation without changing any behavior or geometry.

Because the removed call site is the only consumer of the pill's `accent` variant, the variant is deleted with it — leaving a dead accent path in the private helper would preserve exactly the pattern this change removes.

## Reuse

- The non-accent pill treatment already defined by the `pill()` helper's else-branch: `c.surface` background, `Border.all(color: c.border)`, muted icon, `c.fg` label — the exact variant used by the five sibling pills.
- `context.colors.accent` / `onAccent` remain used only by the intro's `FilledButton` on this screen.
- Exemplar: `lib/screens/home_screen.dart:2644-2649` (sibling pills); `lib/screens/onboarding_screen.dart:460-465` (single-accent-CTA FilledButton pattern).

No new primitive is required; the existing variants fully express the decision.

## Changes

1. `lib/screens/home_screen.dart` — `_buildQuickActions`'s `pill()` helper (lines 2596-2628)
   - Change: remove the `bool accent = false` parameter and the accent branches from the helper, so it unconditionally renders the surface variant: `color: c.surface`, `border: Border.all(color: c.border)`, icon `color: c.muted`, label `color: c.fg`.
   - Preserve: the helper's other parameters (`label`, `icon`, `onTap`), padding (`12` horizontal / `9` vertical), border radius (`10`), row structure, and icon size (`14`).
   - Verify: `pill(...)` compiles with no `accent` argument anywhere in the file.

2. `lib/screens/home_screen.dart` — the `Note` pill call site (lines 2637-2643)
   - Change: replace `pill(label: 'Note', icon: Icons.add, accent: true, onTap: _createNote)` with `pill(label: 'Note', icon: Icons.add, onTap: _createNote)`.
   - Preserve: the `i == 0` positioning as the first pill in the row, the `_createNote` handler, the label "Note", and `Icons.add`.
   - Verify: on Home, the Quick Actions row's first pill renders as a surface pill identical in style to `Expense`/`Income`/`Task`/`Meeting`/`Journal`.

## Scope

- Inherit: the Quick Actions row on desktop Home and mobile Home (both render `_buildHomeScreen`); no other widget consumes `pill()`.
- Verify: the "New note" FilledButton in `_buildHomeIntro` (lines 2338-2347) is unchanged and remains the only accent-filled control on Home; tapping the "Note" pill still creates a note; the continue-working empty row (`_homeQuietRow`, line 2402) and all sibling pills behave as before.
- Exclude: other accent uses on Home and adjacent surfaces that are outside this correction — the pinned-chip pin icons (`home_screen.dart:2563`), the Spent month-card value (`home_screen.dart:2806`), the sidebar's active-item indicator (`lib/widgets/sidebar.dart:500-503`), and the tag-group dots (`lib/widgets/sidebar.dart:677-684`). Do not restyle them in this change; whether they fit the accent budget is a separate, unselected decision. Also exclude the finance screen's accent "Add transaction" control (`lib/widgets/note_list.dart:295-330`) — it is the single CTA of its own screen.

## Validation

- Product: Launch the app → Home → confirm exactly one accent-filled control ("New note") → tap the "Note" pill → a new note is created exactly as before.
- Interface: light and dark mode; spot-check at least Cream, Slate, and Monochrome palettes (Monochrome matters most: its accent is gray `#404040`, and the demoted pill must now read as a neutral sibling rather than a filled gray button next to the gray "New note" button); narrow (<1024 px) and wide viewports; the Quick Actions horizontal scroll still fits all six pills at `SizedBox(height: 38)`.
- System: `grep -n "accent" lib/screens/home_screen.dart` shows no remaining `accent: true`/accent-branch in `_buildQuickActions`; no parallel accent-pill pattern is introduced elsewhere.
- Repository: `flutter analyze` → `No issues found!`; `flutter test` → all existing tests pass.

## Stop conditions

- Stop if `pill()`'s `accent` parameter gains a new call site between plan acceptance and execution — then only remove the `accent: true` argument and keep the parameter.
- Stop if the intro "New note" FilledButton has been removed or redesigned so the "Note" pill is the screen's primary CTA — the discipline would then require the accent to move, not disappear, and this plan no longer applies.
- Stop if `BRANDING.md`'s accent discipline is revised to permit more than one CTA per screen before execution; the change becomes optional and should be re-confirmed.

## Design documentation

- None. The code is being brought into conformance with the existing `BRANDING.md` §3 rule; the documentation already states the accepted decision and must not be edited as part of this change.
