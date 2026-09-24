# Sample finance data appears consistently on every money surface

Written against: commit `0e33c367c14fd99e3045396d096467a77d638211` with the working tree's uncommitted plan-01/02 edits in `lib/screens/home_screen.dart` (Today/Pinned label mappings; single-accent-CTA pill). Line numbers below are working-tree numbers verified by grep.

## Evidence chain

- Surface: Finance tab (Simple and Advanced), Home (CONTINUE row, TODAY overview, THIS MONTH section), note cards, Android finance widget — same session, right after onboarding completes with "Include sample finance entries" checked.
- Problem (rendered, reproduced in `design-plans/rendered-pass/`): Onboarding promises "A demo expense and budget to explore with — remove them later in Settings" (`lib/utils/onboarding.dart`), but the Finance dashboard reports SPENT ₱0.00 / INCOME ₱0.00 / Net ₱0.00 (`d07-finance-simple.png`), "No transactions in this period", and the demo budget at 0% / Spent ₱0.00 (`d08-finance-advanced.png`) — while the Home CONTINUE row shows the same session's sample note as "₱15,180.00 · 2 entries" (`d04-home-desktop.png`), the TODAY card counts "1 transaction", and every note card shows "Net ₱14,820.00". Home's THIS MONTH card is absent for the same reason. The user's first five minutes end on a Finance screen that denies data three other screens display.
- Design evidence:
  - The seeded entries are `isDemo: true`: income 1500000 minor (₱15,000.00, Freelance, dated yesterday) and expense 18000 minor (₱180.00, Food & Drink, dated today), plus a demo budget Food & Drink / 1000000 minor (₱10,000.00) / monthly (`lib/utils/onboarding.dart:195-249`).
  - Exclusion sites that create the contradiction: `lib/screens/home_screen.dart:792` (`_financeSummary`), `home_screen.dart:883` and `:893` (`_budgetActuals`), `home_screen.dart:2764` (`_monthFinanceTotals`), `lib/utils/note_storage.dart:173` and `:211` (`_financePayload` — the Android widget's finance card, which renders the same ₱0.00 contradiction on the home screen widget).
  - Inclusion sites that already display demo data (no change needed): note cards (`_buildCardAmountSpans` in `lib/widgets/note_list.dart` falls back to `note.amounts`), Home CONTINUE/RECENT rows (`_continueSubtitle`, `_buildRecentNotes`), TODAY overview counts (`_buildTodaysOverview`), the Advanced budget list (`lib/widgets/finance_dashboard.dart:265-273` renders all budgets), and JSON/CSV backups (`lib/utils/backup.dart` has no demo filter).
  - Deliberate-exception check: the Advanced budget list already shows the demo budget while its actuals exclude demo spend — the card literally reads "Spent ₱0.00" while a demo expense in its own category (Food & Drink) is visible two screens away. That split cannot be intentional presentation; it is the bug.
- Owner: `lib/screens/home_screen.dart` (summary getters) and `lib/utils/note_storage.dart` (widget payload)
- Scope and affected surfaces: Finance Simple view, Finance Advanced dashboard, Home THIS MONTH section, finance note cards in list mode, Android home-screen widget finance card
- Uncertainty: none for the in-app surfaces. One date-dependent caveat in Validation (seeding uses "yesterday", which falls outside the month on the 1st).

## Design decision

Honor the onboarding promise: until the user removes them via Settings → "Remove sample finance data", the sample entries participate in every **presentation** surface — finance summaries, budget actuals, the Home month card, and the widget payload — exactly as they already do on note cards and Home rows. This makes Finance agree with the rest of the app and makes the demo budget's own card show its sample spend.

Behavioral consumers stay excluded: notification scheduling (`lib/utils/notifications.dart:271,292,306`) keeps skipping demo entries and demo budgets so sample data can never fire reminders or budget alerts, and the ≥60% budget warning banner (`lib/widgets/finance_dashboard.dart:471`) keeps skipping demo budgets. Removal (`_hasSampleData` / `_removeSampleData`, `home_screen.dart:1256-1273`) and onboarding seeding are untouched.

## Reuse

- No new primitives. The change deletes four `isDemo` guards in `home_screen.dart` and two in `note_storage.dart`; every rendered surface already knows how to display the amounts (note cards prove it).
- Exemplar: `lib/widgets/note_list.dart` `_buildCardAmountSpans` — the existing "include demo" presentation the summaries are being aligned to.

## Changes

1. `lib/screens/home_screen.dart` — `_financeSummary` (line 792)
   - Change: delete `if (e.isDemo) continue;`.
   - Preserve: every other filter in the loop (archived/deleted, period, currency scope, income/expense typing).
   - Verify: Finance Simple shows SPENT ₱180.00, INCOME ₱15,000.00, Net ₱14,820.00; RECENT lists the two sample entries; Advanced TOP-SPENDING CATEGORIES lists Food & Drink ₱180.00.

2. `lib/screens/home_screen.dart` — `_budgetActuals` (lines 883 and 893)
   - Change: delete `if (budget.isDemo) continue;` (line 883) and `if (e.isDemo) continue;` (line 893).
   - Preserve: the archived/deleted/type/currency/category filters and the calendar-period start computation.
   - Verify: the Food & Drink budget card renders Spent ₱180.00, Left ₱9,820.00, ~2% progress in Advanced (and any budget bar on finance note cards reflects the sample spend).

3. `lib/screens/home_screen.dart` — `_monthFinanceTotals` (line 2764)
   - Change: delete `if (e.isDemo) continue;`.
   - Preserve: the month window, per-currency buckets, dominant-currency fold.
   - Verify: Home gains a THIS MONTH section: SPENT ₱180.00, INCOME ₱15,000.00 — agreeing with the CONTINUE row above it.

4. `lib/utils/note_storage.dart` — `_financePayload` (lines 173 and 211)
   - Change: delete `if (entry.isDemo) continue;` (line 173) and change line 211's condition from `if (budget.isDemo || budget.period != 'month' || budget.currency != currency)` to `if (budget.period != 'month' || budget.currency != currency)`.
   - Preserve: the month window, dominant-currency selection, budget-selection ranking, payload shape (the Kotlin widget and `test/widget_payload_test.dart` consume it — no test asserts demo exclusion; run the suite).
   - Verify: the Android widget's finance card shows the same month totals as the in-app Finance page for the sample session.

5. Keep, unchanged: `lib/utils/notifications.dart:271,292,306` (demo stays out of reminders/alerts), `lib/widgets/finance_dashboard.dart:471` (demo stays out of the ≥60% warning banner), `home_screen.dart:1256-1273` (`_hasSampleData`/`_removeSampleData`).

## Scope

- Inherit: Finance Simple/Advanced, Home THIS MONTH, finance note cards, the Android widget — all read the changed getters.
- Verify: Settings → "Remove sample finance data" still clears everything (`_hasSampleData` keys on `isDemo`/`_finance` ids — untouched); a fresh onboarding with "Include sample finance entries" unchecked produces the previous all-zero state consistently everywhere; backups/exports (already demo-inclusive) are unchanged.
- Exclude: notification behavior, the warning banner, backup/export logic, the onboarding seeding, and any restyling of how sample entries are labeled — all out of scope.

## Validation

- Product: Complete onboarding with samples → Finance (Simple) shows ₱180.00 / ₱15,000.00 / Net ₱14,820.00; Home shows a THIS MONTH card matching the CONTINUE row; Advanced shows the Food & Drink budget at ₱180.00 spent; the Android widget finance card matches. Settings → Remove sample finance data → every surface returns to a consistent empty state.
- Interface: light and dark; Simple and Advanced; narrow and wide viewports; the sample note open in the editor (its entry list and summary cards already included demo — confirm nothing double-counts visually).
- System: `grep -n "isDemo" lib/` shows the remaining guards only in `notifications.dart`, `finance_dashboard.dart:471`, `_hasSampleData`/`_removeSampleData`, model persistence, and `onboarding.dart` seeding — no presentation-surface guard survives.
- Repository: `flutter analyze` → `No issues found!`; `flutter test` → all pass (including `widget_payload_test.dart`).
- Date caveat: seeding dates the income entry "yesterday". On the 1st of a month the expected INCOME is ₱0.00 / Net −₱180.00 — that is the seeding's behavior, not a regression; validate SPENT ₱180.00 and budget ₱180.00 regardless of date.

## Stop conditions

- Stop if the product intent is instead "samples never appear in totals" — then this plan is wrong and the fix must go the other way (exclude demo from note cards, Home rows, and the TODAY counter), which is a different change requiring its own selection.
- Stop if `_financePayload`'s consumers changed (widget contract) — re-derive the payload shape before editing.
- Stop if budget alerts or reminders are added for demo data during this work — re-examine the notifications exclusions before touching them.

## Design documentation

- None required in `BRANDING.md`. Optional follow-up (not this change): the onboarding copy's promise is now true; no wording change needed.
