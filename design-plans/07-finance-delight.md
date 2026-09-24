# 07 — Finance delight & digestibility

**Problem.** The finance tab is now *honest* (05) and *fast to capture* (06), but it reads like a database report and ends every interaction in silence. Amounts pop in statically; proportion exists only as printed text ("26%"); copy is label-speak ("SPENT", "Left ₱654.25", "Spending 62% vs last month"); the most frequent action — logging an expense — closes its sheet with no confirmation that anything landed; and nothing ever tells the user they're doing *well*. Meanwhile the Home greeting already proves the app can speak like a human ("₱9,140 out · 3 open tasks"). The ask: make finance enjoyable and easier to digest **without moving the layout** and **without violating the brand** (no mascots, no illustrations, no gradients, one accent — BRANDING.md §8/§3).

## Evidence chain

| # | Evidence | Source |
|---|----------|--------|
| E1 | Zero motion in the finance dashboard except the Simple/Advanced toggle; every amount is a static `Text.rich` | finance_dashboard.dart:412-415 (toggle), :1204-1222 (`_SummaryCard`), :673-691 (Simple `_amount`); AppMotion tokens + reduce-motion contract exist unused here (app_motion.dart:34-35) |
| E2 | Label-speak copy: "THIS MONTH/SPENT/INCOME/Net", "RECENT TRANSACTIONS", "Left ₱X", "Overspent ₱X", "Spending 62% vs last month" | finance_dashboard.dart:493,515,525,539,174,1605,1576,1091 |
| E3 | Human voice already shipped on Home: "₱9,140 out · 3 open tasks" — the house style to match | home_screen.dart:2611-2650 (`_buildHomeMetaLine`) |
| E4 | Category rows encode share only as text "$pct%" — no visual proportion anywhere | finance_dashboard.dart:1346-1420 (`_categoryRows`) |
| E5 | Simple card shows SPENT and INCOME as unrelated numbers; their relationship (savings rate) is never drawn or said; Net is a t12 footnote row | finance_dashboard.dart:510-558 |
| E6 | The log moment ends silently: `_save()` → `onSave` → `Navigator.pop`; snackbars exist only for errors/scan; home_screen has `_showSnackBar` infra ("Saved", "Moved to trash") | entry_sheet.dart:201-203,243-247; home_screen.dart:2104 |
| E7 | Budget bars + sparkline bars are static (`LinearProgressIndicator`, `CustomPaint`) | finance_dashboard.dart:1523-1533,737-746; spend_sparkline.dart:106-127 |
| E8 | Recent rows show absolute "M/D" dates — no Today/Yesterday relativity | finance_dashboard.dart:1675 |
| E9 | Nothing celebrates doing well: budgets surface only when ≥60% used ("worth attention"); no on-track state exists | finance_dashboard.dart:467-475 |
| E10 | Streak pattern already in the codebase for writing (`WritingStreak`) — reusable shape for a logging streak | lib/utils/streak.dart |
| E11 | Delta chip is 11px muted text — QA: "subtle (~12-13px vs ~24-28px amounts)" | finance_dashboard.dart:1094; qa-log batch C |

## Design decisions (slices — each lives INSIDE existing cards/sections; nothing moves)

- **D1 — Slice A "Living numbers" (feel).** Hero amounts (summary cards, Simple SPENT/INCOME/Net, sparkline total) count up from 0 on first appear and re-count on period/scope change; budget bars + sparkline bars grow from 0. `TweenAnimationBuilder<double>` + existing `formatMinor`; mono font so digits never jitter; durations from `AppMotion` (slow=320ms for bars, page=450ms for amounts), decelerate curve; **all collapse to static under reduce-motion** via `AppMotion.duration`. Transaction rows do NOT animate (15+ rows = noise + perf).
- **D2 — Slice B "Visible proportion" (digest).** (a) Category rows get a flat proportional fill behind the row content — `accent.withAlpha(~18)` width ∝ share, same card radius; biggest category reads heaviest, zero new chrome. (b) Simple THIS MONTH card gets one 6px two-segment bar under the amounts: spent (destructive) vs kept (income), rendered only when income > 0. (c) Savings rate becomes a first-class human sentence (D3) and a "You kept" stat in the Show-more menu + desktop stats row.
- **D3 — Slice C "Human voice" (digest + feel).** Microcopy pass matching E3's register — warm, factual, no exclamation marks, no guilt: "₱654 left to spend" / "₱70 over budget"; Simple card sentence "You kept ₱31,360 of ₱40,500 this month." (savings-rate %, dominant-currency only, mixed-currency → footnote per 05's honesty rules); delta chip "Spending up 62% from last month" (down → "Spending down X%…", income-green); recent rows "Today / Yesterday / Tue" within 7 days, M/D beyond; **positive state**: when budgets exist and all are <60%, one quiet green line "All budgets on track." (E9). Section headers ("RECENT TRANSACTIONS" etc.) stay — they're the layout's skeleton.
- **D4 — Slice D "The log lands" (feel).** On quick-add save (dock → expense/income sheet): `HapticFeedback.lightImpact()` (mobile) + snackbar "₱185.50 logged · September: ₱9,325.75 out" — amount + running month total in the dominant currency, computed AFTER the save so it includes the new entry. Reuses `_showSnackBar`. Edit-entry saves keep the plain flow (no double noise).
- **D5 — Slice E "Logging streak" (optional, habit).** `computeLoggingStreak` mirroring `WritingStreak` (days with ≥1 non-demo money entry); quiet mono line in the Simple card footer: "Logged 5 days in a row". Encouraging only — NEVER surfaces a broken streak, no guilt copy, hidden at streak < 2. Risk: streaks pressure some users; hence opt-in.

## Changes

1. `lib/widgets/finance_dashboard.dart` — A: count-up wrapper widget + apply to `_SummaryCard`/Simple `_amount`/Net row; B: `_categoryRows` proportional fill, Simple segment bar; C: copy pass (`_BudgetCard`, `_DeltaRow`, `_RecentTransactionRow` dates, Simple sentence, on-track line); E: streak line.
2. `lib/widgets/spend_sparkline.dart` — A: bar grow-in animation (painter takes progress 0→1), reduce-motion aware.
3. `lib/screens/home_screen.dart` — D: haptic + running-total snackbar in the quick-add save path; B/C: pass savings-rate inputs if needed (summary already carries net/income).
4. `lib/utils/finance_utils.dart` — C: `relativeDayLabel(DateTime)` helper (Today/Yesterday/weekday/M-D).
5. `lib/utils/streak.dart` — E: `computeLoggingStreak(notes)` (only if D5 picked).
6. `test/finance_dashboard_test.dart` (+ new `test/finance_voice_test.dart`) — copy assertions, relative-date helper, savings-rate sentence edge cases (income 0, mixed currency), on-track line, streak computation.

## Validation

- `flutter analyze --no-pub` clean; `flutter test` green (76 existing + new).
- `flutter build web --release`; Playwright at 390×844 (Simple + Advanced) and 1440×900 (FinanceWorkspace) with the established fixture; mid-animation screenshot proves count-up; final screenshots → image-analyzer for proportion fill, segment bar, copy, no layout drift vs shots 16/17/21/24.
- Currency-honesty regression: USD scope still shows zero ₱ in summary; mixed-currency savings sentence carries the dominant-currency footnote.
- Reduce-motion: `prefers-reduced-motion` emulation → static numbers, no animation frames.
