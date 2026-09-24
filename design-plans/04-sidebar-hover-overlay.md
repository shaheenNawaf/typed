# Collapsed-sidebar hover opens as an overlay without reflowing the workspace

Written against: commit `0e33c367c14fd99e3045396d096467a77d638211` with the working tree's uncommitted plan-01/02 edits in `lib/screens/home_screen.dart`. `lib/widgets/sidebar.dart` is clean at the commit.

## Evidence chain

- Surface: desktop workspace (`_buildDesktop`), collapsed sidebar state (`sidebarState == 'icons'`), during mouse hover into the left rail and for the ~200 ms after.
- Problem (rendered, reproduced in `design-plans/rendered-pass/`): the collapsed 48 px rail is clean (`d14-sidebar-collapsed.png`), but one hover mid-animation shows the sidebar's expanded content laid out at 232 px while clipped at the animating width — tag names wrap one character per line ("f/i/n/a/n/c/e" under #), section labels clip mid-glyph ("WORKSPAC…", "Tags|"), and the entire workspace content shifts sideways as the Row relayouts (`d15-sidebar-hover-expanded.png`). This fires on every hover into the rail, in both directions.
- Design evidence:
  - `lib/widgets/sidebar.dart:76-84` — `_computeWidth()` returns `_isHovered ? 232.0 : 48.0` for the `'icons'` state, so hover changes the widget's layout width.
  - `lib/widgets/sidebar.dart:91-101` — that width feeds an `AnimatedContainer` with `clipBehavior: Clip.hardEdge` whose child (`_buildContent`) is re-constrained every animation frame, so the expanded layout re-wraps while clipped (the shredded glyphs).
  - `lib/widgets/sidebar.dart:40-74` — `_isHovered`/`_hoverTimer`/`_onHoverEnter`/`_onHoverLeave`/`_effectivelyCollapsed` exist only to drive that width change.
  - `lib/screens/home_screen.dart` `_buildDesktop` — the Sidebar is the first child of the shell `Row`, so its animated width relayouts the whole workspace each frame; the same method computes `sidebarOccupied = _sidebarState == 'expanded' ? 232.0 : 48.0` for the note-list width, a value that silently disagrees with the hovered 232 px reality.
  - The rail's own expand affordance exists independently (bottom chevron toggles collapse via `onCollapse`), so hover-expansion is a convenience layered on top of an explicit control — replacing its mechanics changes no capability.
- Owner: `lib/widgets/sidebar.dart`; shell placement in `lib/screens/home_screen.dart` (`_buildDesktop`)
- Scope and affected surfaces: desktop shell only (`width >= 1024`); the mobile drawer renders `Sidebar` with `sidebarState: 'expanded'` and is untouched
- Uncertainty: none — both defects are visible in the captured mid-animation frame and follow mechanically from the code.

## Design decision

Hover expansion must never participate in workspace layout. In the `'icons'` state the Sidebar always lays out at exactly 48 px; hovering reveals the expanded 232 px panel as an overlay stacked above the workspace, with the panel's content laid out at a fixed 232 px so the reveal animates opacity, never width. The workspace does not move; no text ever re-wraps; the note-list width math (`sidebarOccupied`) becomes correct by construction.

## Reuse

- The overlay panel hosts the existing `Sidebar` widget itself with `sidebarState: 'expanded'` — the full expanded rail (header, nav, tags, pinned, bottom chevron) is reused verbatim, including all callbacks.
- The existing 150 ms close-delay pattern (`_onHoverLeave`'s timer) is preserved in the new overlay so moving from rail to panel does not dismiss it.
- Exemplar: `lib/widgets/sidebar.dart`'s current hover machinery supplies the timing constants; `home_screen.dart`'s shell `Stack` (command palette already overlays the same tree) supplies the placement pattern.

No new primitive is required beyond one small stateful widget introduced next to `Sidebar` in the same file, because the hover state must own both the rail hit-area and the floating panel and no existing widget expresses that pair.

## Changes

1. `lib/widgets/sidebar.dart` — `Sidebar` state and build
   - Change:
     - `_computeWidth()`: return `232.0` for `'expanded'` and `48.0` for `'icons'`/default — drop the `_isHovered` term.
     - Delete `_isHovered`, `_hoverTimer`, `_onHoverEnter`, `_onHoverLeave`, `_effectivelyCollapsed`, and the `MouseRegion` wrapper in `build`.
     - `build` becomes: `AnimatedContainer(duration 200 ms, width: _computeWidth(), clipBehavior: Clip.hardEdge, color: sidebarBg, child: _buildContent(widget.sidebarState != 'expanded', isMobile))`. In the `'icons'` state this container never animates (width is constant at 48).
   - Preserve: the public constructor and every parameter; the expanded-state rendering; `_buildContent`'s collapsed/expanded trees; all other state (`_tagsExpanded`).
   - Verify: hovering the rail no longer changes the Sidebar's layout width.

2. `lib/widgets/sidebar.dart` — new `SidebarHoverOverlay` widget (same file, below `Sidebar`)
   - Change: add a stateful widget that owns the hover lifecycle and renders the panel:
     - Constructor takes exactly the parameters `Sidebar` needs from the shell: `activeFilter`, `onFilterChanged`, `onCollapse`, `onTagFilter`, `onSettings`, `counts`, `allTags`, `tagCounts`, `pinnedNotes`, `onNoteSelected`.
     - State: `bool _open`; `Timer? _hideTimer`. Enter → cancel timer, `_open = true`. Leave → cancel timer, hide after 150 ms.
     - `build`: a 48 px-wide `SizedBox` containing a `Stack(clipBehavior: Clip.none)` with (a) `Positioned.fill(MouseRegion(­opaque: false, onEnter, onExit))` so the rail strip is the hit area while every tap passes through to the real rail underneath, and (b) when `_open`, a panel at `Positioned(left: 0, top: 0, bottom: 0, width: 232)` wrapped in its own `MouseRegion` (same handlers, so entering the panel cancels the pending hide), shown through an `AnimatedSwitcher` (150 ms fade — no width or slide animation).
     - The panel's child is `Sidebar(sidebarState: 'expanded', onCollapse: widget.onCollapse, onFilterChanged: widget.onFilterChanged, onTagFilter: widget.onTagFilter, onSettings: widget.onSettings, counts: widget.counts, allTags: widget.allTags, tagCounts: widget.tagCounts, pinnedNotes: widget.pinnedNotes, onNoteSelected: widget.onNoteSelected)` — the full expanded rail, reused.
   - Preserve: `Sidebar`'s rendering identity inside the panel (it is the same widget).
   - Verify: the panel content is laid out at 232 px from the first frame (no re-wrap); it paints above the note list.

3. `lib/screens/home_screen.dart` — `_buildDesktop`
   - Change: wrap the existing `Row(children: [Sidebar(…), Expanded(…)])` in a `Stack` and add, after the `Row`:
     `if (_sidebarState == 'icons') SidebarHoverOverlay(activeFilter: _activeFilter, onFilterChanged: _setFilter, onCollapse: _toggleSidebar, onTagFilter: _onTagFilter, onSettings: _openSettings, counts: _counts, allTags: _allTags, tagCounts: _tagCounts, pinnedNotes: _pinnedNotes, onNoteSelected: _selectNote)`.
     `sidebarOccupied` is unchanged and now always matches reality.
   - Preserve: the Row and everything inside it; the command-palette overlay ordering (palette must stay above — keep it in the outer `Stack` that already wraps the `LayoutBuilder`, or ensure it is the last sibling of the new inner Stack's parent).
   - Verify: `sidebarOccupied`'s note-list math agrees with the rendered rail at all times.

## Scope

- Inherit: desktop shell only. The mobile drawer passes `sidebarState: 'expanded'` and never sees the overlay.
- Verify: expanded state is pixel-identical to before; the rail's nav taps, settings gear, and bottom chevron still work under the transparent hit-area (`opaque: false` is load-bearing); moving rail → panel keeps it open; leaving either hides it after ~150 ms; clicking a nav item or tag in the panel navigates; the panel's chevron pins the sidebar open (`_toggleSidebar` → `'expanded'`, overlay unmounts); the note list and editor do not move by a single pixel during any hover.
- Exclude: mobile navigation, the expanded (non-collapsed) sidebar, the command palette, and any restyling of the rail or panel contents.

## Validation

- Product: collapse the rail → hover it → the panel fades in above the note list with intact labels; navigate via the panel; hover out → it hides; click the panel's chevron → the sidebar pins open in the Row.
- Interface: before/after pixel comparison of the workspace content column between rail-unhovered and rail-hovered (must be identical); mid-animation frames contain no wrapped or clipped text; light and dark palettes; verify at 1024 px (narrowest desktop) and 1440 px; confirm the command palette still overlays the panel when open.
- System: `grep -n "_isHovered\|_effectivelyCollapsed" lib/widgets/sidebar.dart` → no matches; only one place in the codebase animates the sidebar's width (`AnimatedContainer` for the explicit collapse/expand toggle).
- Repository: `flutter analyze` → `No issues found!`; `flutter test` → all pass.

## Stop conditions

- Stop if hover-expansion is dropped as a wanted feature — then the smaller change is deleting the hover machinery entirely (rail expands only via the chevron), not building the overlay.
- Stop if the shell's desktop layout is restructured (Row → something else) mid-flight — re-derive the overlay's placement and paint order before inserting it.
- Stop if the overlay panel renders underneath the workspace (paint-order regression) — the panel must be the last child of the shell-level Stack; do not ship it painting under the note list.

## Amendment (post-implementation, final mechanism)

The overlay design shipped first but user testing settled the product call differently: a hover-expanded panel covering the workspace behind it was unacceptable — the elements should **move** instead. Final shipped state, restoring this plan's original intent with its jank corrected:

- Hover expansion is back, **pushing** the workspace: `_computeWidth()` returns 232 for the hovered collapsed state, the shell `Row` relayouts, and content slides right — nothing overlays.
- The original push jank (expanded labels re-wrapping one glyph per line mid-animation) is fixed by pinning the expanded layout at its final width: when not collapsed, the content renders inside `OverflowBox(maxWidth: 232, alignment: centerLeft) → SizedBox(width: 232)` under the `AnimatedContainer`'s hard clip, so the animation is a reveal, never a re-constraint.
- The toggle annoyance (sidebar springing back open under the cursor parked inside the rail after a collapse) is fixed by `_suppressHover`: latched in `didUpdateWidget` when the state flips to `icons` while `_pointerInRail` (last enter/exit position ≤ 48 px), cleared only by an exit whose position is genuinely outside the rail zone. Hover state runs through `MouseRegion.onEnter/onExit` position checks; the mobile drawer (`sidebarState: 'expanded'`) never enters hover logic.

Rendered verification: hover over the collapsed rail pushes the workspace right with fully legible labels at every animation frame; leaving collapses it back; a collapse toggle with the cursor parked inside the rail stays collapsed under wiggling; after the pointer genuinely leaves and returns, hover opens it again.

## Design documentation

- None required. The always-dark sidebar and collapse mechanics are unchanged; no documented rule is touched.
