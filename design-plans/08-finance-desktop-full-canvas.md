# 08 — Desktop finance workspace takes the full canvas (prototype Option A)

Status: PLAN (accepted direction — user chose Option A from
`design-plans/proposals/finance-desktop-proposal.html`; that file is the visual spec)
Date: 2026-09-29
Written against: commit `84b9fbb` **plus the uncommitted working tree** (mobile-nav fixes,
`_paneTransition`, period-chip `Expanded`, note-list `Flexible` — all present at plan time).
Re-run the repository checks below before starting; if the working tree changed since,
re-verify the cited line anchors instead of trusting them.

## Evidence chain

- Surface: desktop (≥1024 px) Finance workspace — `FinanceWorkspace` in
  `lib/widgets/finance_dashboard.dart` mounted from `lib/screens/home_screen.dart`
  `_buildDesktop` (finance ternary branch), alongside the note-list pane.
- Problem (observed live at 1440×900, seed data):
  - **F1** — the note-list pane (~340 px, 24 % of canvas) renders one truncated card and
    ~85 % empty space while the dashboard caps itself at `maxWidth: 1080` (≈820 px used).
  - **F2** — "Avg daily spend" renders a permanent em-dash at the default All-time scope
    (`_avgCard` → `valueText: '\u2014'` when `!summary.averageAvailable`), and the
    14-day sparkline is squeezed into a `flex: 2` slot of a 4-up stats row.
  - **F3** — six equal-weight stat boxes; Net is not the hero; the savings rate exists
    only as the "Saved" t22 card + t10 footnote.
- Design evidence: `BRANDING.md` (8 px grid, one accent, mono for numbers, 44 dp),
  `lib/theme/app_colors.dart` — the `warning` token is contracted as *"Budget at 80-100 %
  of its limit. Amber, never red or green"* (current `_BudgetCard` paints that state with
  `accent` instead — contract miss), `lib/theme/app_metrics.dart`, and the accepted
  prototype `design-plans/proposals/finance-desktop-proposal.html` (Option A).
- Owner: `lib/widgets/finance_dashboard.dart` (workspace), `lib/screens/home_screen.dart`
  (pane branching + new callback), `lib/widgets/spend_sparkline.dart` (labels + avg line).
- Scope and affected surfaces: desktop Finance workspace only. Mobile `FinanceDashboardBody`,
  `SimpleFinanceView`, `_ExpandableSummaryCards` (Show-more menu keeps Saved/Avg cards),
  the editor finance block, and the capture flow are untouched.
- Uncertainty: `quick_add_destination_test.dart` pumps the desktop dashboard; verify the
  quick-add destination flow still passes with the pane hidden (see Stop conditions).

## Design decision

Implement prototype Option A on desktop: when Finance is the active workspace the
note-list pane is dropped and `FinanceWorkspace` re-composes to — hero Net card (with the
savings sentence and the spending-delta chip), compact In/Out cards with the mixed-currency
footnote, a promoted full-width 14-day trend card that absorbs ₱/day, a day-grouped ledger
with signed amounts, and the existing right rail (budgets + categories) plus a slim
ledger-note link. This resolves F1 (full canvas), F2 (no dead cards — avg shows only when
computable, total always), and F3 (Net is the hero) without touching mobile, data models,
or capture flow.

## Reuse

- Tokens: `AppColors.*` (incl. the `warning` contract above), `AppSpacing`, `AppRadius`,
  `AppType` — **no new tokens; hero amount uses `AppType.t28`**.
- Helpers: `_labelStyle`, `currencySpan`, `moneySpans`, `formatMinor`
  (`finance_dashboard.dart`); `relativeDayLabel` (`lib/utils/date_format.dart:61`, shipped);
  `CountUpAmount` (`lib/widgets/count_up_amount.dart`).
- Widgets kept as-is: `_SummaryCard` (still used by mobile menu + In/Out), `_RecentTransactionRow`
  (add sign only), `_BudgetCard`, `_categoryRows` (proportional fills already shipped —
  do **not** re-implement), `_ZeroTransactionsState`, `_ScopeSelector`, `_addButtons`.
- Exemplar: the existing `FinanceWorkspace.build` card rows (`finance_dashboard.dart:2160-2200`)
  for padding/radius/spacing conventions; `_moneyKeptCard` (`:1209`) for the savings-rate
  math the hero sentence absorbs.

## Changes

1. `lib/screens/home_screen.dart` — `_hideFinanceListPane` getter (~line 1049)
   - Change: drop the `!_hasAnyFinanceEntries` condition →
     `_activeFilter == 'finance' && !_showEditor`. The list pane now never renders while
     the Finance workspace is up, entries or not.
   - Preserve: the editor branch (`_showEditor`) keeps the list pane; Notes/Tasks/etc.
     keep the pane everywhere; the `noteListW` math is untouched.
   - Verify: at 1440×900 with seeded entries, Finance shows the workspace across the full
     content width (~1160 px); opening a note brings the list pane back.

2. `lib/screens/home_screen.dart` — desktop finance branch (~line 2263)
   - Change: pass two new optional params to `FinanceWorkspace`:
     `ledgerNoteLabel` = title of the most recently updated visible finance note
     (`notes.where(isVisibleFinanceNote)…` — reuse the existing filter, no new getter), and
     `onOpenLedgerNote: () => _selectNote(thatNote.id)`. Null-safe: when no finance note
     exists, pass null and the link card must not render.
   - Preserve: all existing params and callbacks (`onSelectEntry`, `dailyTotals: _last14DaySpend`, …).
   - Verify: the dashed link in the workspace's right rail opens the monthly note in the editor.

3. `lib/widgets/finance_dashboard.dart` — `FinanceWorkspace` signature + `build` (~2160-2210)
   - Change: add `final String? ledgerNoteLabel;` + `final VoidCallback? onOpenLedgerNote;`
     (optional, default null). Raise the `ConstrainedBox` maxWidth from 1080 to 1200.
     Re-compose the children list:
     a. scope row (unchanged);
     b. **hero row** — `_NetHeroCard` (flex 3) + In card (flex 2) + Out card (flex 2),
        replacing the old Income/Expenses/Net row **and** the stats row
        (Transactions/Saved/Avg/sparkline cards are removed from this workspace);
     c. **trend row** — `SpendSparkline` promoted to its own full-width card
        (see change 5) with `showDayLabels: true`;
     d. two-column row — ledger (flex 3) + right rail (flex 2), as today.
   - Preserve: `_DeltaRow`'s widget class stays (mobile menu may reference the pattern) but
     it is no longer mounted by `FinanceWorkspace`; the savings-rate math moves into the hero
     (`_moneyKeptCard` the helper function stays — `_ExpandableSummaryCards` still uses it).
   - Verify: the workspace shows exactly: scope row, hero row, trend row, two-column row.

4. `lib/widgets/finance_dashboard.dart` — new `_NetHeroCard` (private, same file)
   - Change: card styled `color: surface`, `border: accentDim`-tinted (no gradient). Content:
     label "Net · <periodName(period)>" via `_labelStyle`; amount `formatMinor(summary.net)`
     with `currencySpan`, `AppType.t28` mono w700, colored income/destructive/muted by net
     sign (same rule as today's `_netCard`); the savings sentence
     "You kept **₱X of ₱Y** this month · Z %" — reuse `_moneyKeptCard`'s computation and
     exclusion footnote ("excl. USD") verbatim; income ≤ 0 renders the em-dash placeholder
     pattern instead of the sentence. Below: the spending delta chip.
   - Change: extract the chip body of `_DeltaRow` (`finance_dashboard.dart:1127-1151`) into a
     private `_DeltaChip` widget (t11 → keep t11, add `incomeDim`/`expenseDim`-tinted
     background + `borderRadius: AppRadius.chip`); hero renders the spending chip only when a
     previous period exists (same guard as `_DeltaRow`).
   - Preserve: mixed-currency rules — sentence and net use dominant currency only; never sum
     across currencies (reuse `_dominantFirst` if the In/Out cards need stacked lines).
   - Verify: with the 05 seed fixture (PHP + USD), the hero sentence carries the
     "excl. USD" footnote and the delta chip reads "Spending down N% from last month".

5. `lib/widgets/spend_sparkline.dart` + workspace row
   - Change: add `showDayLabels` (default false) — under each bar, the day-of-month in
     `AppType.t10` mono muted; zero days draw the existing dashed stub. Add an optional
     `averagePerDay` param: when > 0, a dashed `warning`-colored horizontal line at the avg
     height with a right-aligned "₱X / day" mono caption, and "· ₱X / day" appended to the
     header row. Increase default height 56 → 96 when labels are shown. Bars keep
     `accent.withAlpha(110)` + solid-accent today (unchanged).
   - Change (workspace): pass `averagePerDay: summary.averageAvailable
     ? summary.averageDailySpend.round() / 100 …` formatted via `formatMinor` — render the
     avg affordances only when `averageAvailable` is true (at All-time scope the card shows
     the 14-day total alone; no em-dash anywhere). Delete `_avgCard` if nothing else
     references it after this (grep first).
   - Preserve: `TweenAnimationBuilder` grow-in, `AppMotion` reduce-motion contract,
     `CountUpAmount` total.
   - Verify: 14 dated bars + avg line at Month scope; total-only at All scope.

6. `lib/widgets/finance_dashboard.dart` — `_transactionsColumn` day grouping (~2269)
   - Change: group `summary.recentEntries` by calendar day (already sorted desc —
     `allEntries.sort` in `home_screen.dart`), newest first. Between groups render a
     day header via `relativeDayLabel(date)` ("Today", "Yesterday", "Tue · Sep 23") in
     `AppType.t10` mono uppercase muted. Rows keep `_RecentTransactionRow` and the existing
     `onSelectEntry`/`onSelectNote` fallback chain.
   - Change: `_RecentTransactionRow` amount becomes signed — prefix `+` for income,
     `−` (U+2212) for expense, before `currencySpan` in the same `Text.rich` (color already
     encodes direction; the sign is the a11y-non-color cue from 05-D1).
   - Preserve: the empty-state branch with "View all time" (`onViewAllTime`) unchanged.
   - Verify: ledger shows day headers and signed amounts; tapping a row still opens the
     EntrySheet for that entry.

7. `lib/widgets/finance_dashboard.dart` — `_BudgetCard` warning color (~1582-1589)
   - Change: `pct >= 80` branch paints `context.colors.warning` instead of
     `context.colors.accent`, per the `warning` token contract in `app_colors.dart`
     ("Budget at 80-100 % … Amber"). Align the header pct text color with `barColor`.
   - Preserve: over-budget destructive state, "over budget" line, bar fill/animation,
     44 dp `_BudgetAction` targets.
   - Verify: a budget at 81-99 % renders an amber bar; 100 %+ stays destructive.

8. `lib/widgets/finance_dashboard.dart` — ledger-note link in the right rail
   - Change: after the budgets section, when `ledgerNoteLabel != null`, render a
     `Border.all(color: border)` dashed-style card (`AppRadius.card`, 12 px padding):
     `article` icon (14, muted) + "September's ledger lives in" muted t12 +
     `ledgerNoteLabel` (fg, w500) + "Open ›" (accent, t12, right-aligned), whole card an
     `InkWell` → `onOpenLedgerNote`. Min height 44 dp.
   - Preserve: nothing renders when the param is null (fresh install, no finance notes).
   - Verify: the card opens the monthly note; hidden when no finance note exists.

## Scope

- Inherit: desktop Finance users get the full-canvas workspace; the ledger note stays
  reachable via the link card, #finance tags, command palette, and ledger rows.
- Verify: `test/finance_dashboard_test.dart` — many tests pump `FinanceWorkspace` directly
  (lines ~294-463) and assert `'Transactions'`, `'Last 14 days'`, `'Saved'` etc.; update
  assertions to the new composition (count may move into the section header, Saved/Avg
  cards are gone at desktop, day headers appear). `test/quick_add_destination_test.dart`
  pumps the desktop shell — confirm the quick-add destination flow still resolves.
  `test/mobile_hub_smoke_test.dart` / `mobile_shell_geometry_test.dart` are mobile-only —
  must pass untouched.
- Exclude: mobile `FinanceDashboardBody` / `SimpleFinanceView` / `_ExpandableSummaryCards`;
  the editor finance block; `EntrySheet` / capture flow; `NoteList` widget itself; any
  chart beyond the extended sparkline painter; new dependencies (none needed).

## Validation

- Product: run the app (`flutter run -d web-server`) at 1440×900 with the seeded fixture;
  Finance must match the accepted prototype: full-width workspace, hero Net with sentence +
  delta chip, In/Out with exclusion footnote, dated 14-day bars with avg line, day-grouped
  signed ledger, amber 81 % budget, over-budget 106 % budget, category fills, ledger-note
  link. Also 390×844 (mobile unchanged) and 1024×768 (desktop minimum — hero row must not
  wrap; if it does, drop In/Out sub-lines first, not the cards).
- Interface: All/Week/Month/Year × All-currencies/USD scopes; zero-transactions state
  (`_ZeroTransactionsState` + budgets, unchanged); income-only month (hero em-dash
  sentence path); mixed-currency fixture (footnotes, no summing).
- System: no parallel patterns — the hero reuses `_moneyKeptCard` math and `_labelStyle`;
  day headers reuse `relativeDayLabel`; nothing new introduces a second label style,
  radius, or accent usage beyond BRANDING's discipline.
- Repository: `flutter analyze` → no issues; `flutter test` → all green (after the
  assertion updates in Scope).

## Stop conditions

- Stop and re-scope if hiding the list pane breaks the quick-add destination flow or
  `_findOrCreateMonthlyFinanceNote` discovery in a way the link card cannot recover —
  the pane's navigational role would need a different home first.
- Stop if `averageAvailable` proves unreliable at scope boundaries (avg line rendering
  wrong at Week/Month) — ship the trend card without the avg line rather than guessing.
- Stop if the hero row cannot fit 1024 px without dropping the sentence (F3's core)
  — escalate rather than shrinking to the old six-box layout.

## Design documentation

- After acceptance and validation, in the same change:
  1. Append to `design-plans/05-finance-dashboard-usability.md` under Recommendation:
     "2026-09-29 — Option A of the desktop proposal shipped (slice A completed:
     full-canvas workspace, F2/F3 residue from this plan); remaining slices B/C/D unchanged."
  2. Add a one-line status header to
     `design-plans/proposals/finance-desktop-proposal.html`:
     `<!-- STATUS: Option A accepted 2026-09-29; implemented per design-plans/08 -->`.
  3. Note in `lib/theme/app_colors.dart`? No — the `warning` contract is already
     documented; the code now conforms to it.
