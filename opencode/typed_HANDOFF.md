# Typed — Design Handoff for Flutter / Android

Complete specification to recreate the three-pane Markdown note-taking app on any platform. Reference: `inkwell-note-app.html` (1282 lines, single-file prototype).

---

## 1. Design System

### 1.1 Color Tokens

All colors use **OKLCH** for perceptual uniformity. Flutter/Dart: convert with `dart_oklch` or approximate with sRGB hex/LAB.

**Light theme (canonical)**

| Token | OKLCH value | Role | Pixel share |
|---|---|---|---|
| `--bg` | `oklch(99% 0.002 240)` | Page/app background | 100% |
| `--surface` | `oklch(100% 0 0)` | Card, editor, toolbar backgrounds | 50% |
| `--fg` | `oklch(18% 0.012 250)` | Primary text | — |
| `--muted` | `oklch(54% 0.012 250)` | Secondary text, placeholders, icons | — |
| `--border` | `oklch(92% 0.005 250)` | Separators, card borders, toolbar edges | — |
| `--accent` | `oklch(52% 0.18 25)` | Links, selection, CTA, footnote markers | ≤10% |
| `--accent-dim` | `oklch(52% 0.18 25 / 0.12)` | Selection glow, preview toggle active bg | transition |

**Dark sidebar (always dark, independent of theme)**

| Token | OKLCH value | Role |
|---|---|---|
| `--sidebar-bg` | `oklch(22% 0.012 255)` | Sidebar background |
| `--sidebar-fg` | `oklch(88% 0.005 255)` | Sidebar text, icons |
| `--sidebar-muted` | `oklch(60% 0.01 255)` | Sidebar secondary text, tag labels |
| `--sidebar-active` | `oklch(30% 0.012 255)` | Active nav item background |
| `--sidebar-hover` | `oklch(28% 0.012 255)` | Sidebar hover background |

**Note list (mid panel)**

| Token | OKLCH value | Role |
|---|---|---|
| `--list-bg` | `oklch(96% 0.003 250)` | Note list panel background |

**Tag chips**

| Token | OKLCH value | Role |
|---|---|---|
| `--tag-bg` | `oklch(52% 0.18 25 / 0.10)` | Tag pill background |
| `--tag-fg` | `oklch(42% 0.15 25)` | Tag pill text |

**Accent discipline:** Max 2 visible uses of `--accent` per screen. Typical pair: selected note card border + one CTA/active state.

### 1.2 Typography

| Token | Value | Usage |
|---|---|---|
| `--font-display` | `'Outfit', -apple-system, BlinkMacSystemFont, sans-serif` | Headings, card titles, editor title |
| `--font-body` | `'Outfit', -apple-system, BlinkMacSystemFont, sans-serif` | Body text, UI labels, nav items |
| `--font-mono` | `'JetBrains Mono', 'IBM Plex Mono', ui-monospace, monospace` | Code, word count, timestamps, counts |

**Scale:**

| Role | Size | Weight | Line-height | Letter-spacing |
|---|---|---|---|---|
| Editor title | 22px | 600 | 1.3 | -0.015em |
| Markdown H1 | 24px | 700 | 1.3 | -0.02em |
| Markdown H2 | 20px | 600 | 1.3 | -0.015em |
| Markdown H3 | 17px | 600 | 1.3 | -0.01em |
| Card title | 14.5px | 600 | 1.5 | -0.01em |
| Body / Editor text | 15px | 400 | 1.7/1.55 | 0 |
| Nav items | 13.5px | 400 | 1.5 | 0.01em |
| Uppercase labels | 13px | 500 | 1.5 | **0.06em** (all-caps rule) |
| Tag children | 12.5px | 400 | 1.5 | 0.01em |
| Card preview | 12px | 400 | — | — |
| Card meta / timestamp | 11.5px | 400 | — | 0.02em |
| Word count | 11px | 400 | — | 0.04em |
| Caption / kbd hints | 11px | 400 | — | 0.04em–0.06em |

**Weight system (Outfit):** 400 (read), 500 (emphasize), 600 (announce/strong/buttons), 700 (display H1 only).

### 1.3 Spacing + Sizing

| Variable | Value | Where |
|---|---|---|
| `--sidebar-w` | 232px | Default sidebar width |
| `--sidebar-icons-w` | 48px | Collapsed/icons-only sidebar |
| `--notelist-w` | 340px | Note list column width |
| `--toolbar-h` | 48px | Editor toolbar height (not enforced as const) |
| `--title-h` | 64px | Editor title bar height (not enforced as const) |

**Spacing vocabulary:**
- Sidebar nav items: `6px 12px` padding
- Note cards: `14px 16px` padding, `4px` gap, `10px` border-radius
- Editor body: `16px 24px` padding
- Toolbar buttons: `34×34px` hit area, `8px 14px` toolbar padding, `2px` gap
- Sidebar header: `16px 18px 12px`

**Border radii:**
- Sidebar nav items: `6px`
- Tag parent/child: `6px` / `4px`
- Note cards: `10px`
- Toolbar buttons: `6px`
- Tag chips: `4px` (editor), `12px` (editor tag bar)
- Search input: `8px`
- Code blocks: `8px`

---

## 2. Layout Architecture

### 2.1 Three-Pane Grid

```
+----------------+-------------------+--------------------------+
|   SIDEBAR      |    NOTE LIST      |       EDITOR             |
|   (dark)       |    (light gray)   |       (white)            |
|   232px        |    340px          |       1fr                |
+----------------+-------------------+--------------------------+
```

CSS: `grid-template-columns: var(--sidebar-w) var(--notelist-w) 1fr`

**Collapse states (cycle: expanded → icons → hidden → expanded):**

| State | Grid columns | Sidebar behavior |
|---|---|---|
| `expanded` | `232px 340px 1fr` | Full sidebar with labels |
| `icons` | `48px 340px 1fr` | Icons only; hover flies out to 232px (desktop only) |
| `hidden` | `0px 340px 1fr` | Sidebar fully hidden; toolbar button restores it |

Hover flyout on icons mode: 150ms debounce before collapse. Flyout dismissed on click outside interactive elements.

### 2.2 Responsive Breakpoints

| Breakpoint | Layout |
|---|---|
| `< 1024px` (mobile) | Single-column stack with fixed mobile nav bar at bottom. Each pane is full-width; sidebar slides in from left (280px, `translateX`). Editor overlays full screen. |
| `≥ 1024px` (desktop) | Three-pane grid. Mobile nav, overlay, and back button hidden with `!important`. |

**Mobile pane switching:**
- Sidebar: slides in from left with overlay backdrop (tap overlay to close, Escape key also closes)
- Note list: always visible as "home" pane
- Editor: full-screen overlay (`position: fixed; inset: 0`) with back button at top
- Bottom nav bar: 3 tabs — Tags (opens sidebar), Notes (closes editor), New (creates note + opens editor)

---

## 3. Component Inventory

### 3.1 Sidebar

```
┌─────────────────────┐
│ [logo] Typed  [⟨] │  ← header: logo + collapse toggle
├─────────────────────┤
│ [icon] Notes    24  │  ← .nav-item.active (first one by default)
│ [icon] Untagged 3   │
│ [icon] Todo     7   │
│ [icon] Today    2   │
│ [icon] Locked   1   │
│ [icon] Archive  5   │
│ [icon] Trash    —   │
├─────────────────────┤
│ ▶ personal          │  ← .tag-parent-btn (open/closed via .open class)
│   family/health     │  ← .tag-child (indented 44px)
│   journal           │
│ ▶ code              │
│   js                │
│   python            │
│   rust              │
│   algo              │
│ ▶ study             │
│   cs                │
│   math              │
│   design            │
│ blog post           │  ← .tag-leaf (indented 36px, no children)
│ recipe              │
│ travel              │
├─────────────────────┤
│ close sidebar       │  ← bottom bar (text button)
└─────────────────────┘
```

**Interactive elements:**
- **`.nav-item`:** Clickable. Adds `.active` class (sidebar-active bg, white text). Filters note list by view on click.
- **`.tag-parent-btn`:** `<button>` with `aria-expanded="true/false"`. Toggles `.open` on itself and `nextElementSibling`. Chevron rotates 90° (`transform: rotate(90deg)`) when open. Children use `max-height: 0 → 400px` transition (0.25s ease).
- **`.tag-child`:** `<button data-filter="parent/child">`. Sets search input value, filters notes. Adds `.active` class on click, removes from siblings.
- **`.tag-leaf`:** `<button data-filter="tag">`. Same as child but no parent group.
- **Collapse button:** Cycles 3 states. Icon changes each state.

**States per interactive:** default, hover (sidebar-hover bg), focus-visible (2px accent outline, offset -2px), active.

### 3.2 Note List

```
┌─────────────────────┐
│ [Search notes...   ]│  ← search input (filter on input)
│ ALL NOTES     [A-Z]│  ← h2 + sort toggle button
├─────────────────────┤
│ ┌─────────────────┐ │
│ │ Rust Ownership  │ │  ← .note-card (surface bg, 10px radius)
│ │ 📄 #code/rust..│ │     title 14.5px/600, tags in chips, meta 11.5px
│ │ 2 hours ago     │ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │ Binary Search   │ │  ← .note-card.selected (accent border + glow)
│ │ 📄 #code/algo..│ │
│ │ Yesterday       │ │
│ └─────────────────┘ │
│        ...          │
└─────────────────────┘
```

**Card preview icon logic:**
- PDF/JPG/DOCX attachment → `<span class="preview-filetype">` badge with file icon + extension text
- No attachment → document icon SVG (14×14px, stroke only)
- Inline tag chips with tag-bg/tag-fg colors

**Interactive elements:**
- **Search input:** Filters notes on `oninput` (title, content, tag match). Shows `.no-results` div ("No notes match your search.") when no results.
- **Sort button:** Toggles between "Recent ↓" and "A–Z ↑". Sorts by `title.localeCompare()`.
- **Note card:** `tabindex="0" role="button" aria-label="title"`. Click selects note. Arrow Up/Down navigates, Enter selects. `.selected` class adds accent border + `box-shadow: 0 0 0 2px var(--accent-dim)` with smooth transition.
- **No results:** Centered text, hidden when results exist.

### 3.3 Editor

```
┌─────────────────────┐
│ ← Notes (mobile)    │  ← .mobile-back (only on <1024px)
├─────────────────────┤
│ [Note title...]     │  ← .editor-titlebar input (22px/600)
│ #tag1 #tag2         │  ← .editor-tags (flex wrap, pill badges)
├─────────────────────┤
│                     │  ← .editor-body-wrap (scrollable)
│ Markdown content    │
│ or preview          │
│                     │
├─────────────────────┤
│ B I ` H1 H2 🔗 • ☑│  ← .editor-toolbar (floating at bottom)
│ › " |table|  0 w Pv│
└─────────────────────┘
```

**Empty state (no note selected):**
- Centered document icon (48×48px, 25% opacity)
- "Select a note or create a new one"
- Kbd hint: "Cmd+N — new note"
- "+ New Note" button

**Toolbar buttons (10 total):**

| Button | Action | Markdown inserted |
|---|---|---|
| B | `insertMD('**','**')` | `**text**` |
| I | `insertMD('*','*')` | `*text*` |
| ` | `insertMD('`','`')` | `` `text` `` |
| H1 | `insertLine('# ')` | `# text` at line start |
| H2 | `insertLine('## ')` | `## text` at line start |
| Link | `insertMD('[','](url)')` | `[text](url)` |
| Bullet list | `insertLine('- ')` | `- text` at line start |
| Checklist | `insertLine('- [ ] ')` | `- [ ] text` at line start |
| Blockquote | `insertLine('> ')` | `> text` at line start |
| Table | `insertMD('\n\| Col 1 \| Col 2 \|\n...')` | Table skeleton |

**Preview toggle:** Swaps between `<textarea>` and rendered HTML `<div>`. `.tb-toggle.on` state has accent-dim bg + accent text. `aria-pressed` attribute updated. Text changes "Preview" ↔ "Edit".

**Word count:** Lives in toolbar right section. `updateWordCount()` splits textarea value by whitespace. Displayed as `"N w"` in monospace.

### 3.4 Mobile Nav Bar

```
┌─────────────────────┐
│   ≡         📋      +│
│  Tags    Notes   New│
└─────────────────────┘
```

Fixed to bottom on `< 1024px`. Three buttons with icon + label. Active state = accent color. `env(safe-area-inset-bottom, 8px)` for notched devices. Hidden when editor is open (`body.has-editor-open`).

---

## 4. Interaction Patterns

### 4.1 Keyboard Shortcuts

| Key | Action |
|---|---|
| `Cmd/Ctrl + N` | Create new note |
| `Cmd/Ctrl + B` | Bold |
| `Cmd/Ctrl + I` | Italic |
| `Arrow Up/Down` | Navigate note cards (when focused in list) |
| `Enter` | Select focused note card |
| `Escape` | Close sidebar (mobile) |

### 4.2 Sidebar Collapse Toggle (Desktop Only)

Cycle: **expanded → icons → hidden → expanded**

- **expanded → icons:** Sidebar shrinks to 48px. Nav items become icon-only (labels + counts hidden). Tag tree hidden. Hover over sidebar expands to 232px with 150ms debounce collapse.
- **icons → hidden:** Sidebar width = 0. Entire sidebar display:none. Same on mobile: closes sidebar drawer.
- **hidden → expanded:** Full sidebar restored.

"close sidebar" bottom button: on mobile → closes drawer; on desktop expanded → collapses to icons.

### 4.3 Title Auto-Create

Typing in the title field when no note is selected calls `createNote(title)`. The note is created with the typed title, inserted at the top of the list (`unshift`), and selected.

### 4.4 Word Count Update Triggers

- Direct `oninput` on textarea
- After `syncTitle()` saves content
- After `renderPreview()` renders markdown

### 4.5 Content Sync

`insertMD()` and `insertLine()` both call `syncTitle()` + `renderPreview()` after insertion. `syncTitle()` saves `textarea.value` to `note.content` and `titleInput.value` to `note.title`. `renderPreview()` runs a regex-based markdown-to-HTML converter that handles: h1–h3, bold, italic, code, links, blockquotes, fenced code blocks, task lists, bullet lists, tables, horizontal rules, and inline `#tag` chips.

---

## 5. Data Model

### 5.1 Note Object

```dart
class Note {
  String id;       // 'n' + DateTime.now().millisecondsSinceEpoch
  String title;    // editable, default 'Untitled'
  String content;  // raw Markdown string
  List<String> tags;  // e.g. ['code/rust', 'code/algo']
  String time;     // relative: "Just now", "2 hours ago", "Yesterday", "July 15"
  String? att;     // file extension badge or null: 'PDF', 'JPG', 'DOCX', etc.
}
```

### 5.2 Tag Structure

Tags use slash notation for nesting: `personal/family`, `code/rust`, `study/math`. The sidebar renders them as a hierarchy:

```
personal
  family/health
  journal
code
  js
  python
  rust
  algo
```

Each note stores the full qualified tag path (e.g. `code/rust`). The tag tree is currently static (hardcoded HTML) — dynamic extraction from notes' tags array is a planned feature.

### 5.3 App State

```dart
String? currentNoteId;      // null = no note selected → show empty editor
bool sortDesc = true;       // true = newest first (Recent ↓)
String activeFilter = 'notes'; // 'notes' | 'untagged' | 'todo' | 'today' | 'locked' | 'archive' | 'trash'
bool previewMode = false;   // true = rendered HTML visible, textarea hidden
String sidebarState = 'expanded'; // 'expanded' | 'icons' | 'hidden'
```

**Filter logic:**
- `notes` → all notes
- `untagged` → `tags.length == 0`
- `todo` → title contains 'todo' OR content contains `[ ]`
- `today` → first note only (placeholder)
- `locked`/`archive`/`trash` → empty (not implemented)

---

## 6. Accessibility (A11y)

### 6.1 Implemented

- All 10 toolbar buttons + 3 mobile nav buttons have `aria-label`
- Tag tree uses semantic `<button>` elements with `aria-expanded`
- Note cards: `tabindex="0" role="button" aria-label="title"`
- Preview toggle uses `aria-pressed`
- Sidebar nav has `role="navigation"` + `aria-label`
- `:focus-visible` styles on ALL interactive elements (2px accent outline, offset varies by context)
- Keyboard navigation: Arrow Up/Down + Enter on note cards, Escape closes sidebar
- Dark sidebar: all text meets 4.5:1 contrast on `oklch(22%…)` background

### 6.2 To Implement in Flutter

- `Semantics` widgets on all interactive elements
- TalkBack/VoiceOver labels matching `aria-label` values
- Focus traversal order: sidebar → note list → editor (LTR reading order)
- Keyboard support via `Focus` and `Shortcuts` widgets
- Sufficient tap targets (≥44px on mobile, ≥48dp on Android)

---

## 7. Animations & Transitions

| Element | Property | Duration | Easing |
|---|---|---|---|
| Nav item hover | background | 0.12s | ease (implicit) |
| Tag child hover | color, background | 0.12s | ease |
| Tag chevron rotation | transform: rotate | 0.18s | ease |
| Tag children expand | max-height | 0.25s | ease |
| Sidebar slide (mobile) | transform: translateX | 0.25s | ease |
| Search input border | border-color | 0.15s | ease |
| Note card selection | border-color, box-shadow | 0.15s | ease |
| Toolbar button | background, color | 0.12s | ease |
| Preview toggle | background, color | 0.12s | ease |
| Sidebar hover flyout (icons mode) | debounce timeout | 150ms | — |

**Flutter equivalents:**
- Hover/active: `AnimatedContainer` or `MaterialStateProperty` with 120–180ms durations
- Expand/collapse: `AnimatedCrossFade` or `AnimatedSize` with `Curves.ease` (0.25s)
- Slide transitions: `SlideTransition` / `AnimatedPositioned` with `Curves.ease` (0.25s)
- Selection glow: `AnimatedContainer` with `BoxDecoration` border + `BoxShadow`

---

## 8. Markdown Parsing (Regex Sequence)

The editor runs a sequence of regex replacements in this order (order matters):

1. `### (.+)` → `<h3>$1</h3>`
2. `## (.+)` → `<h2>$1</h2>`
3. `# (.+)` → `<h1>$1</h1>`
4. `\*\*(.+?)\*\*` → `<strong>$1</strong>`
5. `\*(.+?)\*` → `<em>$1</em>` (must run after bold)
6. `` `([^`]+)` `` → `<code>$1</code>`
7. `\[(.+?)\]\((.+?)\)` → `<a href="#">$1</a>`
8. `!\[(.+?)\]\((.+?)\)` → image placeholder span
9. `^> (.+)$` → `<blockquote>$1</blockquote>`
10. Fenced code blocks → `<pre><code>$2</code></pre>`
11. `- [x] (.+)$` → task item done
12. `- [ ] (.+)$` → task item unchecked
13. `- (.+)$` → `<li>$1</li>`
14. Pipe tables → `<table>` (regex: `\|(.+)\|\n\|[-\s|]+\|\n((?:\|.+\|\n?)*)`)
15. `^---$` → `<hr>`
16. `#([a-zA-Z][\w/]*)` → `<span class="tag-chip">#$1</span>`
17. `\n\n+` → `</p><p>` (paragraph wrapping)
18. Lines → `<br>`

Post-processing: unwrap `<p>` from block elements (lists, tables, blockquotes, code blocks, headings, hrs).

---

## 9. Platform-Specific Notes for Flutter

### 9.1 Widget Equivalents

| Web Element | Flutter Widget |
|---|---|
| Three-pane CSS Grid | `Row` with 3 `Expanded`/`SizedBox` children |
| `.sidebar` | `NavigationRail` or custom `Container` with dark bg |
| `.notelist` | `ListView.builder` with custom `Card` items |
| `.editor` | `Column` with `TextField` + `SingleChildScrollView` |
| `.editor-textarea` | `TextField(maxLines: null, expands: true)` |
| `.editor-preview` | `Markdown` widget (flutter_markdown) or `HtmlWidget` |
| `.note-card` | `Card` or `InkWell` + `Container` with `BoxDecoration` |
| `.tag-chip` | `Chip` or `Container` with `BorderRadius.circular(4)` |
| `.mobile-nav` | `BottomNavigationBar` or `BottomAppBar` |
| Sidebar slide-in | `Drawer` |
| `.tb-btn` (toolbar) | `IconButton` with `SizedBox.square(34)` |

### 9.2 Packages to Consider

| Need | Flutter Package |
|---|---|
| Markdown rendering | `flutter_markdown` |
| Rich text editing | `super_editor` or custom `TextEditingController` |
| Syntax highlighting | `flutter_highlight` |
| Local storage | `sqflite` / `drift` for notes DB, `shared_preferences` for app state |
| Font | `google_fonts` (`Outfit`) |
| Icons | `lucide_icons` (matches SVG icon style) or `phosphor_flutter` |

### 9.3 Dark Sidebar on Android

The sidebar is always dark regardless of system theme. Use a `DecoratedBox` with `oklch(22% 0.012 255)` background — this is approximately `#2D2F33` in sRGB hex.

### 9.4 Tag-Based Navigation

Instead of folder-based, notes are organized by `List<String> tags`. Build the tag tree by:
1. Collect all unique tags from all notes
2. Split each by `/`
3. Build a Trie/tree structure
4. Render as expandable list tiles with indentation

### 9.5 Search Implementation

Full-text search across title, content, and tags. In Flutter, use `sqflite` FTS (full-text search) or filter in-memory with `where()`.

---

## 10. Not Yet Implemented (Roadmap)

Features described in the brief but not yet in the HTML prototype:

- [ ] Note locking (password/biometric)
- [ ] OCR search inside images/PDFs
- [ ] Export to TXT, MD, RTF, PDF, HTML, DOCX, JPG, ePub
- [ ] Cross-device sync (backend-agnostic)
- [ ] Multiple themes (dark/light variants)
- [ ] Sketches/drawings inline
- [ ] Outline folding (collapse sections under headings)
- [ ] Live tag extraction from body text (auto-scan `#tag` patterns)
- [ ] Pin important tags; custom tag icons
- [ ] Real Today/Locked/Archive/Trash filters (currently stubs)
- [ ] Undo/redo
- [ ] Multi-cursor editing

---

*Generated from `inkwell-note-app.html` — a 1282-line single-file web prototype using the Modern Minimal design direction with Outfit typeface and warm red accent.*
