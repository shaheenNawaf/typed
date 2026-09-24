# 05 — Finance Dashboard Usability

Status: PROPOSAL (discovery complete, awaiting direction choice)
Date: 2026-09-20
Surfaces audited: finance_dashboard.dart, home_screen.dart (finance getters + desktop layout),
note_list.dart (finance pane), entry_sheet.dart, budget_sheet.dart, editor.dart (finance block),
context_panel.dart, settings_sheet.dart, notifications.dart, note_storage.dart, recurrence.dart.
Live QA: Flutter web release @ 390×844 + 1440×900, seeded fixture (Sep 2026, mixed PHP/USD,
3 budgets incl. one overspent). 15 screenshots + accessibility-tree verification; every number
below was observed running, not inferred. Artifacts: `.orchestrator/qa/` (gitignored).

## Problem

The dashboard is functionally complete but fails three user-facing jobs:
1. **Trust** — displayed numbers silently disagree with each other when currencies mix.
2. **Glanceability** — core answers (trend, all budgets, full transaction list) are hidden,
   capped, clamped, or absent; there is no visualization of any kind.
3. **Flow** — tapping a transaction doesn't take you to it; logging one takes detours; the
   desktop (primary workspace) wastes 51% of its width.

## Evidence chain (observed live)

| # | Observation | Evidence |
|---|-------------|----------|
| E1 | Currency scope = USD → summary cards show $0.00/$9.99 while BUDGETS section still renders ₱770.50/₱2,345.75/₱545.00, no explanation anywhere | shot 07 + image-analyzer |
| E2 | Budget at 110% of limit displays "100%" (clamped); overspend magnitude only in small "Overspent ₱70.50" text | shots 03/12 + code `_BudgetCard` |
| E3 | Simple view shows exactly ONE budget warning (Food & Drink 110%); Groceries at 78% silently suppressed | shot 01 + code `SimpleFinanceView` |
| E4 | "AVG DAILY SPEND" stat card renders the literal text "Mixed currencies" instead of a number at the DEFAULT All-currencies scope | shot 06 + image-analyzer |
| E5 | Advanced cards use ISO codes ("PHP 14,790.75 \| USD 9.99" joined text); Simple view and editor use ₱ — two notations for the same data | shots 01 vs 03 |
| E6 | Editor finance summary (₱9,140.25) silently excludes the USD $9.99 entry — note total ≠ sum of its visible rows | shot 13 + code editor.dart:1141-1160 |
| E7 | Desktop 1440×900: sidebar ≈230px + dashboard ≈475px + EMPTY editor ≈735px ("Select a note to start editing"); delta chip truncates to "Spending 62% vs last …" in the narrow column | shot 12 + image-analyzer |
| E8 | Tapping RECENT row "Lunch with team" opens the PARENT NOTE in the editor; the entry itself is not opened, highlighted, or scrolled to (13 entries, user must re-find it) | shot 13 + code home_screen.dart:1305-1327 |
| E9 | Editor entry rows on a Sep 2–20 note all display "12:00" — time only, no date; rows in insertion order, not date order | shots 13/15 + code editor.dart:1369-1376, 1181-1187 |
| E10 | Create FAB on Finance tab → generic "New note" dialog with 7 templates (4 of them note templates); Quick expense then creates a **PHP** note even while dashboard scope is **USD** | shots 08/09 + code home_screen.dart:523 |
| E11 | Entry sheet: Date field hidden inside collapsed "Show details" on EVERY open; validation is SnackBar-only (can hide behind keyboard) | shots 09/10 + code entry_sheet.dart:539-565, 242-246 |
| E12 | RECENT capped at 5 (simple: 4), categories capped at 4, no "see all" anywhere; no flat transaction list exists in the app — list is note-centric | shots 01/03 + code |
| E13 | Zero charts/sparklines/trends; an empty `// Spending Trends` comment sits at finance_dashboard.dart:1172 | shot 01 + image-analyzer ("no charting of any kind") |
| E14 | Touch targets: editor row pencil/X ≈20-24px; budget edit/delete IconButtons 28×28 — below BRANDING.md 44dp minimum | shot 15 + image-analyzer + code |
| E15 | Mobile: FAB occludes the 3rd category row's amount; note-card subtitle truncates to "Mixed cur…" | shot 03 + image-analyzer |
| E16 | Net/Transactions/Avg Daily Spend live behind a "Show more" popup (one at a time, ephemeral); menu gives no hint that picking one REPLACES the card | shots 05/06 + image-analyzer |

## Proposed slices

### Slice A — Desktop finance workspace (E7, E8, E12, part of E29-truncation)
When the Finance tab is active on desktop (≥1024px) and no note is open, the dashboard renders
in the WIDE pane instead of the 280-340px column: two-column layout (summary+budgets left,
transactions+categories right), full-width cards, no chip truncation. Transaction row tap opens
the ENTRY (EntrySheet in edit mode) directly — parent-note navigation moves to a secondary
affordance (row's note subtitle tap or an icon). Optional: "See all" on RECENT expands to a
full flat transaction list (date-sorted desc, signed amounts) in the wide pane.
Files: home_screen.dart `_buildDesktop`, finance_dashboard.dart, note_list.dart.
Risk: medium (layout branching + navigation semantics). Highest visible impact.

### Slice B — Currency & budget honesty (E1, E2, E3, E4, E5, E6)
1. Budgets section respects the currency scope: under a specific-currency scope show only that
   currency's budgets; under All-currencies group by currency with explicit labels.
2. Unclamp budget percent: show 110%, bar fills to 100% + over-bar segment in destructive color.
3. Simple view: show up to 2 warnings + "N more need attention" row (tap → advanced budgets).
4. Avg Daily Spend with mixed currencies: compute in dominant currency, label "₱457/day in PHP"
   (+ "excl. USD" footnote) instead of the dead-end "Mixed currencies" text.
5. One notation: ₱ symbol everywhere (currencySpan already handles the glyph); multi-currency
   totals render as stacked per-currency lines, not "A | B" joined text.
6. Editor summary: add "+ $9.99 USD" indicator line when non-dominant entries are excluded.
Files: finance_dashboard.dart, home_screen.dart (`_financeSummary`, `_budgetActuals`),
editor.dart (finance block). Risk: low-medium (pure presentation + filter logic; no schema change).

### Slice C — Capture speed (E10, E11, E19-hardcoded-PHP)
1. Finance tab FAB → direct action sheet with exactly 2 options (Add expense / Add income),
   skipping the note-template dialog (templates remain on Notes/Home tabs).
2. Quick-add inherits the dashboard's selected currency (falls back to PHP only when scope=All).
3. Entry sheet: compact Date row visible by default (above Show details); inline validation
   text under Amount/category instead of SnackBar-only.
4. Edit mode: remove the dead "Add & Next" slot; add Delete action to the sheet.
Files: note_list.dart (FAB), home_screen.dart `_quickAddTransaction`/`_findOrCreateQuickNote`,
entry_sheet.dart. Risk: low. Improves the daily loop most.

### Slice D — Glanceable rows & targets (E9, E12-signs, E14, E15, part of E13)
1. Transaction rows everywhere (dashboard RECENT + editor): signed amounts (+₱40,500.00 /
   −₱185.50), keeping color as secondary cue (a11y: not color-only).
2. Editor entry rows: show M/D (or M/D/YY across year boundary) instead of time-only; sort rows
   date-desc; group multi-day notes under day headers.
3. Touch targets to ≥44dp: editor pencil/X rows, budget edit/delete buttons.
4. Mobile: bottom content padding so FAB never occludes the last category row.
5. Optional starter trend: 14-day spend sparkline bars in the summary area (fills the empty
   "Spending Trends" slot; CustomPainter, no new dependencies).
Files: finance_dashboard.dart, editor.dart, note_list.dart. Risk: low.

## Recommendation

**A + B first** (desktop is the primary workspace; trust defects undermine everything else),
then **D** (row-level polish compounds with A), then **C** (capture flow is a separate loop and
can ship independently). Slices are disjoint enough to spec/verify one at a time.

## Validation plan (per slice)

- `flutter analyze` clean + `flutter test` green (8 existing test files; add widget tests for
  new filter/format logic where pure).
- Rebuild web release; Playwright QA against the same seeded fixture at 390×844 and 1440×900;
  screenshots → image-analyzer with closed-ended questions tied to the acceptance criteria in
  `.orchestrator/frame.md` (items 1-7 map to slices A/B/C/D).
- BRANDING.md compliance per change: ≤2 accent uses per screen, 8px grid, Outfit/JetBrains Mono,
  44dp targets, no gradients/secondary accent.
