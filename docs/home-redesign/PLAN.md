# Home redesign: implementation plan

Approved: 2026-11-06, from the v4 prototype (`prototype.html` in this folder).
Goal: make Home different every day, using data the app already has. It should feel more alive without getting busier.

Open `prototype.html` in a browser to see every state. The left phone in section 1 is the real app, screenshotted with the data in `seed-data.html`. Everything else is the proposal, drawn in the app's own type, colours and spacing.

---

## 1. What changes, in one table

| Block today | Becomes | Borrowed from |
|---|---|---|
| **Next up**: one task, freshest list first, date shown inside the text | **Today**: overdue first, then the rest of today, grouped into Any time, Morning, Afternoon and Evening; **Later** becomes **Tomorrow** | Todoist and Things 3 (one Today list, overdue first); Apple Reminders (time-of-day groups) |
| **For tomorrow** (after 6 PM, only when nothing is open) | **Left from today** (move leftovers to tomorrow) + **Tomorrow** list | Structured's Replan |
| **Money line**: "₱4,660 spent in November", below the fold | **Until payday**: "₱5,340 left until the 15th · about ₱593 a day · On pace"; on payday, a summary of the last cutoff | Kaban (PH), Copilot Money |
| **Pick up where you left off**: one note, often the Welcome note | **Recent**: the 3 latest notes, lists and voice memos | Notion Home |
| — | **Last week** card on Mondays, hideable | Monarch Money's weekly recap |
| "Swipe up for more" pill (covers content) | Removed from Home | — |
| To-do + Finance widgets | **Today widget**: what's next plus money until payday | Samsung Now Brief (not on the S23) |
| From your notes, capture bar, header, dock | **Unchanged** | — |

It also fixes two bugs visible in `shots/real-before.png`:
1. **The date leaks into task text:** "Call the dentist — Fri, Nov 6, 2 PM".
2. **The overdue task is skipped:** Next up shows the most recently edited list instead.

---

## 2. Block order on Home

```
Intro (date · greeting · subline)
Capture bar
[ Moment card ]   ← at most one: Payday (on a payday) or Last week (on Monday)
Today             ← evening: Left from today + Tomorrow (see §4)
Until payday      ← not shown on payday (the moment card replaces it)
Recent
From your notes   ← unchanged
```

Each block hides itself when it has nothing to say. Never show an empty card.

**Subline:** first matching rule wins.

| Situation | Text |
|---|---|
| Payday | "Payday. **N for today.**" |
| Monday morning | "New week. **N for today.**" |
| Evening, leftovers | "**D done today.** K left over." |
| Evening, none left | "**D done today.** Here's tomorrow." |
| Items today, none done | "**N for today**, M from yesterday." (the second part only when there are overdue tasks) |
| Some done | "**L left today.** D done." |
| Nothing due | "Nothing due today. A good day to write." |

---

## 3. Phase 1: Today (and the two bug fixes)

### 3.1 Dates on task lines

Voice memos already save dated tasks as `- [ ] <text> — <label>`, where `<label>` is `SpokenWhen.label` from `lib/voice/when_parser.dart`. Examples:

- `Fri, Nov 6`
- `Fri, Nov 6, 2 PM`
- `Fri, Nov 6, 2:30 PM`
- `Fri, Nov 6, morning` (also afternoon / evening / tonight)

New file **`lib/utils/task_dates.dart`**, pure functions with no UI:

- `TaskDate? parseTaskDate(String line, DateTime now)` returns `(text, SpokenWhen when)`. It splits on the **last** ` — `, then parses the label back into a date.
  - **Year:** the label has no year, so pick the year that puts the date closest to `now`, within ±6 months. Example: "Thu, Jan 2" said in December means next year.
  - **Bad labels:** if the text after ` — ` isn't a valid label, the line is undated and the text stays as written. Normal prose like "Plan — big picture" must survive.
- `String withTaskDate(String text, SpokenWhen? when)` writes the line back using the same `label`.
- `SpokenWhen moveToDay(SpokenWhen w, DateTime day)` keeps the time or part of day.

Typed or edited lines get no date unless they follow this format. Reading other date styles is out of scope.

### 3.2 What goes in Today

New file **`lib/home/today_plan.dart`**. The pure function `TodayPlan buildTodayPlan(List<Note> notes, DateTime now)` covers the same open checklist lines as `_upNextItems()` (`home_screen.dart:3420`): every non-archived, non-deleted, non-seed note.

**Classes of item:**
- **overdue:** the date is before today.
- **today:** the date is today. It's timed if it has an hour or a part of day.
- **undated:** no date.
- **future:** after today. Left out, except from Tomorrow in the evening.

**Focus card:** the first item from this order:
1. overdue, oldest first
2. today with a time, by time
3. today without a time
4. undated, freshest note first

**Rows under the focus card:** grouped in this order.
- **Overdue** (only if there's more than one)
- **Any time:** dated today with no time, plus undated tasks (at most 3, freshest first)
- **Morning:** before 12:00
- **Afternoon:** 12:00–16:59
- **Evening:** 17:00 or later

A part of day maps straight to its group: morning, afternoon, or evening/tonight. Show at most 6 rows; beyond that, add "+N more", which opens the Tasks tab.

**Quiet day:** nothing overdue and nothing due today.
- One row: ✓ "Nothing due today." with "N tasks in your lists have no date." under it.
- Below that, up to 2 undated tasks, each with **Do today**, which adds today's date to the line.
- On a busy day, undated tasks sit in Any time instead.

### 3.3 Widget: `HomeToday` (replaces `HomeNextUp` in `home_modules.dart`)

**Focus card.** Keep the existing card exactly as it is (`_taskCard`, `home_modules.dart:464`), with these changes:
- **Title** is the text with the date removed.
- **Under the title:** a chip, then "in <list>".
  - Overdue: a warning chip, e.g. "Due yesterday", "Due Tue", "Due Nov 2".
  - Timed today: an accent chip with the time.
  - Undated: no chip.
- **Buttons:** Done and **Tomorrow**.
  - Tomorrow moves the date to tomorrow and keeps the time. An undated task gets tomorrow's date.
  - Show "Moved to tomorrow" with Undo.
- **Keep:** the Done animation, the 360 ms delay, the haptics, and the "Done: …" snackbar with Undo.

**Rows:** the task text on the left, then the time right-aligned, then a bell if a reminder is set. Group headers are 10.5 px, uppercase, muted.

**Label row:** "TODAY", with "All tasks →" on the right.

### 3.4 Reminders when a date changes

Task reminders are keyed by `noteId|line` (`lib/utils/notifications.dart`, `task_reminders_v1`). When Tomorrow or Do today rewrites a line:

1. Read the reminder for the old line.
2. If one existed and the new date has a time, schedule a new reminder for the new line at the new date and time.
3. The old reminder is cancelled automatically by `_reconcileTaskReminders`, because the old line no longer exists.

Add a helper: `NotificationService.moveTaskReminder(noteId, oldLine, newLine, DateTime? at)`.

### 3.5 Remove

- Delete `_upNextItems` ordering by freshest note (replaced by `buildTodayPlan`).
- Delete "Later" and its per-session set-aside queue.

### 3.6 Tests

**`test/task_dates_test.dart`:**
- Every label form round-trips.
- Year inference across Dec/Jan.
- An unknown suffix is left as plain text.
- `moveToDay` keeps the time.

**`test/today_plan_test.dart`:**
- Focus order.
- Grouping boundaries at 11:59, 12:00, 16:59 and 17:00.
- Part-of-day mapping.
- The 6-row cap.
- The quiet-day switch.
- Future items are excluded.

**Widget tests, updating `home_engagement_test.dart` and `home_feed_test.dart`** (these assert "NEXT UP" and "Later" today):
- Overdue comes first.
- The date suffix is not shown in the title.
- Tomorrow rewrites the line, and Undo restores it.
- On a quiet day, Do today adds today's date.

---

## 4. Phase 4: evening (Left from today + Tomorrow)

Applies from 18:00, using `HomeScreen.clock`.

- **Tasks still ahead tonight:** if any Today item has a time later than now, Today stays at the top and Tomorrow goes under it.
- **Otherwise:**
  - **Left from today:** open items that were due today or overdue. Undated tasks don't count.
    - Buttons: **Move to tomorrow**, which moves all of them, and **Leave it**, which hides the card for tonight (`leftover_dismissed_day_v1` = epoch day).
  - **Tomorrow · Sat, Nov 7:** items dated tomorrow, grouped like Today, then an add row "Add something for tomorrow" (`TaskAddRow`).
    - Added items go to Inbox with tomorrow's date (`_captureTask` plus `withTaskDate`).
- **Delete `HomeWindDown`.**
- **Tests:** the switch at 18:00, the "later tonight" exception, Move to tomorrow, Leave it, and adding for tomorrow.

---

## 5. Phase 2: Until payday

### 5.1 Settings (`settings_sheet.dart`, Finance section)

- **Payday:** "Twice a month: 15th and 30th" (default), "15th and last day", "Once a month on…", or "Custom (two days)".
  - Stored as `payday_v1` = `{"days":[15,30]}`.
  - A day past the end of a month moves to the last day (30 becomes Feb 28/29).
- **Budget per cutoff:** optional amount in the finance currency.
  - Stored as `cutoff_budget_v1` = `{"amount":<minor>,"currency":"PHP"}`.
  - This is separate from the per-category monthly budgets (`Budget`, period week/month/year), which stay as they are.

### 5.2 Maths (`lib/utils/cutoff.dart`, pure)

`Cutoff currentCutoff(PaydaySettings, DateTime now)` returns:
- **start:** the most recent payday on or before today
- **end:** the day before the next payday
- **totalDays**
- **dayIndex:** 1-based
- **daysLeft:** counting today

`CutoffMoney cutoffMoney(notes, cutoff, budget, now)`:
- **spent:** expense entries in [start, today].
  - Use the same filters as `_monthFinanceTotals` (`home_screen.dart:3753`): visible finance notes (`isVisibleFinanceNote`), not `isDemo`, dominant currency.
  - Income is ignored.
- **ideal** = budget × dayIndex / totalDays
- **left** = budget − spent
- **perDay** = left / daysLeft
- **todaySpent:** used for the evening footer.
- **topCategory:** used for the payday summary.

**Status:**
- **On pace:** spent ≤ ideal × 1.05.
- **Over pace:** show "₱X over pace" in the warning colour.
- **Over budget:** show "₱X over budget" in the expense colour, with the bar full.

### 5.3 Card (`HomePaydayCard` in `home_modules.dart`)

**With a budget:**
- Label "UNTIL PAYDAY", with "Money →" on the right.
- "₱5,340" (26 px, w700), followed by "left until the 15th" in muted text.
- A 6 px bar showing spent, with a 2 px accent tick at the ideal point.
- Footer: "About ₱593 a day for 9 days" and "✓ On pace".
- In the evening the footer reads "₱1,235 logged today" instead.

**Without a budget:**
- "₱4,660 spent since Oct 31" and "about ₱666 a day".
- A quiet **Set a budget** link.

**Never logged any money (non-demo):** hide the card.

**Tapping the card** opens the Finance tab.

### 5.4 Payday moment

On a payday, until **Later** is tapped or the day ends (`payday_card_seen_v1` = epoch day), a card takes the top moment slot in place of Until payday:
- "Last cutoff · Oct 31 – Nov 14"
- "₱1,180 kept" in the income colour, or "₱X over" in the warning colour
- A bar
- "₱8,820 of ₱10,000 · most on Food"
- Buttons: **Start new cutoff**, which opens the budget amount pre-filled with the last one, and **Later**.
- Without a budget: "₱8,820 spent last cutoff · most on Food".

### 5.5 Tests

**`test/cutoff_test.dart`:**
- The 15th/30th split.
- February.
- 31-day months.
- Today is a payday.
- A once-a-month payday.
- Budget, no budget and over budget.
- Demo entries are excluded.

**Widget tests:**
- The card text in each state.
- Tapping opens Finance.
- The payday card, and Later hiding it.

---

## 6. Phase 3: Recent, and removing the hint

**`HomeRecent`** replaces `HomeContinueCard`.
- **Which notes:** the 3 most recently updated. Exclude archived, deleted, seed (`isSeedNote`), `guide` and finance notes. Include lists.
- **Each row:**
  - **Icon:** `mic_none` if tagged `voice`, `check_circle_outline` for a list, `article` otherwise.
  - **Title.**
  - **Subtitle:** "Voice memo · …" for voice; "X of Y done" for a list; otherwise the first line of the preview (`_continueSubtitle` logic).
  - **Relative time.**
- **Label:** "RECENT", with "All notes →" on the right.
- Hide the block if there are no items.
- Remove `_continueNote` and `HomeContinueCard`.
- **Remove the "Swipe up for more" pill from Home** (`_buildDockHint`, `home_screen.dart:3132`). Keep the `dock_swipe_hint_seen_v1` key so old installs stay quiet. See open question 3.
- **Tests:** update the expected blocks in `home_feed_test.dart`, check Recent's order and filters, and check the pill is gone.

---

## 7. Phase 5: Last week (Mondays)

- **Shown:** on Monday, unless hidden (`recap_hidden_v1` = Monday's epoch day), and only if last week had any activity. It takes the moment slot; payday wins if both apply.
- **Data:**
  - **Tasks done per day:** a new `done_log_v1` = `{epochDay: count}`, written by `_countDone` (`home_screen.dart:2090`) next to `done_today_v1`. Prune entries older than 35 days.
    - The first week after the update has no history, so show "—" for tasks.
  - **Notes:** created last week; not seed, finance or voice.
  - **Voice memos:** notes tagged `voice` created last week.
  - **Spending:** per day (the bars) and the total.
  - **Top category change against the week before:** show it only if it's at least ₱200 and at least 20%.
- **Card:**
  - Three numbers: tasks done · notes · voice memos.
  - 7 bars, with the biggest day highlighted.
  - "₱3,140 spent. Food ↑ ₱600 vs the week before, mostly Thursday."
  - **Hide** on the label row.
- **New file:** `lib/home/week_recap.dart` (pure).
- **Tests:** aggregation, the change threshold, a missing done log, Hide, and payday taking priority.

---

## 8. Phase 6: Today widget (Android)

- **New** `TodayWidget.kt` + `today_widget.xml`, using the existing patterns in `android/app/src/main/kotlin/com/z4yed/typed/`.
  - Default 4×2, resizable to 4×4.
  - Include a preview image and a description, per Google's widget-quality guidance.
- **Header:**
  - The "t." mark.
  - "Friday · 3 for today".
  - A mic button (intent `voice`) and a + button (intent `new`).
- **Rows:** the order from `buildTodayPlan`, showing as many as fit. Each has a tick circle and a right-aligned time, or "Yesterday" in the warning colour.
  - Ticks reuse `widget_pending_toggles_v1` + `toggle:<id>:<text>`, which the existing To-do widget already uses.
- **Money strip:** "₱5,340 until the 15th · ₱593 a day", with a bar.
- **Payload:**
  - `widget_today_v1`, written in `NoteStorage._writeWidgetPayload` (`note_storage.dart:130`).
  - It stores **absolute** dates, budget, spent, cutoff start and end.
  - Kotlin works out "Yesterday" and the per-day amount when it draws.
- **Staleness:** schedule a refresh at midnight (inexact alarm via `WidgetBootReceiver`/`WidgetHelper`) so the labels don't go stale.
- **Old widgets:** keep the existing To-do and Finance widgets working (people may have placed them), but list Today first. See open question 4.
- **Testing:** test the payload in Dart. Check the widget by hand on the S23 using the beta APK, since there's no emulator.

---

## 9. Code layout

**New files (pure, unit-tested):**
- `lib/utils/task_dates.dart`
- `lib/utils/cutoff.dart`
- `lib/home/today_plan.dart`
- `lib/home/week_recap.dart`

**New widgets** in `lib/widgets/home_modules.dart`, reusing the existing pieces (`HomeCard`, `HomeLabel`, `TaskCheck`, `TaskAddRow`):
- `HomeToday`
- `HomeLeftovers`
- `HomeTomorrow`
- `HomePaydayCard`
- `HomePaydaySummary`
- `HomeRecent`
- `HomeWeekRecap`

**`home_screen.dart`:** only the wiring changes, in `_buildHomeScreen` (3350) and callbacks. Don't add more logic to this 3,857-line file; it belongs in the new files.
- **Optional, later:** move the Home tab into `lib/screens/home/home_tab.dart`.

**Visual tokens:**
- Card radius 18, with a hairline border at 80% alpha and no shadow.
- Labels 11 px, w600, letter-spacing 0.9.
- Focus task 18 px, w500.
- Chips 11.5 px, w600: warning for overdue, accent for a time.
- Ink buttons: the `fg` colour as the fill, 40 px tall.
- Group headers 10.5 px.
- Rows 15 px, with the time 13 px muted and right-aligned.

---

## 10. Delivery

Each phase gets its own branch from `main`, its own PR and its own beta APK on GitHub releases. The user merges each one.

| # | Phase | Size | Release |
|---|---|---|---|
| 1 | Today + date fixes | M | v0.3.0-beta.1 |
| 2 | Until payday + settings + payday card | M | beta.2 |
| 3 | Recent + remove hint | S | beta.3 |
| 4 | Evening: leftovers + tomorrow | S–M | beta.4, then **v0.3.0** |
| 5 | Monday recap + done log | S–M | v0.3.1-beta.1 |
| 6 | Today widget | M–L | v0.3.1 |

**Per PR:**
1. `flutter analyze`, the full `flutter test`, `flutter build web --release` (Netlify) and `flutter build apk --release --target-platform android-arm64`.
2. Check the output contains "√ Built" before uploading.
3. Check the uploaded asset's SHA-256 against the local file.

**Visual check against the prototype:**
1. Run `flutter build web`.
2. Serve `build/web` with `seed-data.html` copied next to it, plus a `frame.html` that loads `index.html` in a 390×844 iframe.
3. Screenshot with headless Edge (`--window-size=390,844 --force-device-scale-factor=2 --virtual-time-budget=30000`).
4. Compare the screenshot with `prototype.html`.
5. Notes on the seed data:
   - Prefs live in localStorage as `flutter.<key>`, with JSON-encoded values.
   - `notes_v1` is a JSON string.
   - Finance notes use type `expense`.
   - Every note needs `content`.

**Repo hygiene:**
- `tools/voice_model/` (23 files) is currently **deleted from disk but still in git**. Never stage those deletions.
- Stage paths explicitly instead of using `git add -A`.
- Push and release as `shaheenNawaf`, with a per-command token (see memory).

---

## 11. Open questions (defaults in bold; build with the defaults unless the user says otherwise)

1. **Payday default:** **15th and 30th** (Feb becomes the last day), or 15th and the last day of the month?
2. **Recurring bills in the pace maths:** **included** (Typed's recurring entries are real entries), or left out like Copilot does?
3. **Finding Spaces and Settings without the swipe pill:** **rely on swipe-up plus Search for now.** A later option is a one-time tooltip, or a menu button in the header (it was in the v1 prototype).
4. **Old To-do and Finance widgets:** **keep them alongside Today**, or retire them after v0.3.1?
5. **"Customise Home"** (show or hide blocks, like Notion): **not in this round.** It's useful later for people who don't track money.

---

## 12. Done when

- [ ] Section 1 of `prototype.html` matches the web build screenshotted with `seed-data.html`.
- [ ] No task title on Home shows ` — <date>`.
- [ ] An overdue task is always the focus card.
- [ ] Tomorrow, Do today and Move to tomorrow rewrite dates, keep reminders, and can be undone.
- [ ] Until payday is right on the 14th, 15th, 30th and 31st, and in February.
- [ ] Only one moment card shows at a time, and no block renders empty.
- [ ] All tests pass, analyze is clean, and the web and APK builds succeed.
