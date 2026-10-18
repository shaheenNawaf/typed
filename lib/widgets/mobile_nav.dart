import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// Mobile dock, after the iOS 26 tab bar and Things' standalone Magic Plus:
///
/// * a frosted-glass capsule sized to its four tabs (not a full-width strip),
/// * Create as its own round key beside it, never a slot inside the bar,
/// * a selection lens that glides between tabs (no stretch, no bounce),
/// * a filled glyph for the active tab, outlines for the rest,
/// * [collapsed]: while you scroll down to read, the capsule shrinks to the
///   current tab so the content gets the screen; tapping it opens it again.
///
/// Everything happens at the bottom, in thumb reach:
/// * swipe up on the capsule → [onOpenNavigation] (the rest of the app:
///   spaces, pinned, tags, Settings); a grabber line hints at it, and
///   screen readers get it as a named action;
/// * slide along the capsule to scrub between tabs — the lens follows the
///   finger and the tab is chosen on release.
///
/// Icon-only for sighted users; labels go to screen readers and tooltips.
class MobileNav extends StatefulWidget {
  final String currentTab;
  final ValueChanged<String> onTabChanged;
  final VoidCallback onCreate;

  /// Minimized while the page scrolls down; see [onExpand].
  final bool collapsed;

  /// Asked for when the minimized capsule is tapped.
  final VoidCallback? onExpand;

  /// Swipe up on the dock: opens the full navigation sheet.
  final VoidCallback? onOpenNavigation;

  const MobileNav({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
    required this.onCreate,
    this.collapsed = false,
    this.onExpand,
    this.onOpenNavigation,
  });

  /// Total vertical space the dock occupies above the safe-area inset, so
  /// pages scrolling underneath can pad their ends.
  static const double occupiedHeight =
      _MobileNavState._keySize +
      18 +
      _MobileNavState._grabberHeight +
      _MobileNavState._grabberGap;

  @override
  State<MobileNav> createState() => _MobileNavState();
}

class _NavTab {
  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavTab(this.id, this.icon, this.activeIcon, this.label);
}

class _MobileNavState extends State<MobileNav>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    _NavTab('home', Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavTab('notes', Icons.article_outlined, Icons.article, 'Notes'),
    _NavTab(
      'finance',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      'Finance',
    ),
    _NavTab('tasks', Icons.check_circle_outline, Icons.check_circle, 'Tasks'),
  ];

  /// One height for the capsule AND the Create key, so the two read as a pair.
  static const double _keySize = 64;

  // The capsule is symmetric: the lens sits [_inset] from every edge and the
  // icons are centred in it. The grabber line floats just ABOVE the capsule
  // (like a home indicator), so it never crowds the icons.
  static const double _inset = 6;
  static const double _lensH = _keySize - _inset * 2;
  static const double _grabberHeight = 4;
  static const double _grabberGap = 6;
  static const double _maxSlot = 56;
  static const double _gap = 10;
  static const double _sidePad = 16;

  /// Tab slot width: 56 when there is room, narrower on small phones so the
  /// capsule and the Create key always fit (320px screens included).
  double _slot = _maxSlot;
  static const double _lensHeight = _lensH;

  late final AnimationController _lens = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  double _from = 0;
  double _to = 0;

  /// Slot under the finger while scrubbing along the capsule.
  int? _scrubIndex;

  /// Upward travel of the current vertical drag; opens navigation once.
  double _rise = 0;
  bool _opened = false;

  int get _activeIndex {
    final i = _tabs.indexWhere((t) => t.id == widget.currentTab);
    return i == -1 ? 0 : i;
  }

  bool get _hasActive => _tabs.any((t) => t.id == widget.currentTab);

  @override
  void initState() {
    super.initState();
    _from = _to = _activeIndex.toDouble();
    _lens.value = 1;
  }

  @override
  void didUpdateWidget(MobileNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      // Start from wherever the lens is right now, so rapid taps chain.
      _from = _lensPosition;
      _to = _activeIndex.toDouble();
      if (MediaQuery.disableAnimationsOf(context)) {
        _lens.value = 1;
      } else {
        _lens.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _lens.dispose();
    super.dispose();
  }

  void _moveLensTo(int index) {
    _from = _lensPosition;
    _to = index.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _lens.value = 1;
    } else {
      _lens.forward(from: 0);
    }
  }

  void _scrubTo(double dx) {
    final index = ((dx - _inset) / _slot).floor().clamp(0, _tabs.length - 1);
    if (index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
    HapticFeedback.selectionClick();
    _moveLensTo(index);
  }

  void _endScrub() {
    final index = _scrubIndex;
    if (index == null) return;
    setState(() => _scrubIndex = null);
    if (index != _activeIndex) {
      widget.onTabChanged(_tabs[index].id);
    } else {
      _moveLensTo(_activeIndex);
    }
  }

  void _openNavigation() {
    if (widget.onOpenNavigation == null) return;
    HapticFeedback.lightImpact();
    widget.onOpenNavigation!();
  }

  double get _lensPosition {
    final t = Curves.easeOutCubic.transform(_lens.value);
    return ui.lerpDouble(_from, _to, t)!;
  }

  @override
  Widget build(BuildContext context) {
    // The safe-area inset can be bogus in embedded/preview contexts
    // (hundreds of px), which would float the dock to the middle of the
    // screen — clamp it like the original bar did.
    final bottomInset = MediaQuery.of(context).padding.bottom.clamp(0.0, 50.0);
    return Padding(
      // Top room holds the grabber line above the capsule.
      padding: EdgeInsets.fromLTRB(
        _sidePad,
        8 + _grabberHeight + _grabberGap,
        _sidePad,
        10 + bottomInset,
      ),
      child: SizedBox(
        // The Scaffold bottomNavigationBar slot is bounded-loose in height;
        // a fixed height keeps the dock from expanding.
        height: _keySize,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final room = constraints.maxWidth - _keySize - _gap - _inset * 2;
            _slot = (room / _tabs.length).clamp(40.0, _maxSlot);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _capsule(context),
                const SizedBox(width: _gap),
                _CreateKey(size: _keySize, onCreate: widget.onCreate),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _capsule(BuildContext context) {
    final collapsed = widget.collapsed && _hasActive;
    final width = collapsed ? _keySize : _slot * _tabs.length + _inset * 2;
    final glass = _Glass(
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.base),
        curve: Curves.easeOutCubic,
        width: width,
        height: _keySize,
        // The full row keeps its natural width while the capsule grows
        // around it (clipped), instead of being squeezed into 64px.
        child: collapsed
            ? _collapsedTab(context)
            : ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: _slot * _tabs.length + _inset * 2,
                  maxWidth: _slot * _tabs.length + _inset * 2,
                  child: _tabRow(context),
                ),
              ),
      ),
    );
    if (widget.onOpenNavigation == null) return glass;
    final grabbable = Stack(
      clipBehavior: Clip.none,
      children: [
        glass,
        // Grabber: says "this pulls up" without a word. Outside the glass so
        // it is never clipped and never crowds the icons.
        Positioned(
          top: -(_grabberHeight + _grabberGap),
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 28,
              height: _grabberHeight,
              decoration: BoxDecoration(
                color: context.colors.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Open navigation'): _openNavigation,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _rise = 0;
          _opened = false;
        },
        onVerticalDragUpdate: (d) {
          _rise -= d.delta.dy;
          if (!_opened && _rise > 28) {
            _opened = true;
            _openNavigation();
          }
        },
        onVerticalDragEnd: (d) {
          if (!_opened && (d.primaryVelocity ?? 0) < -250) {
            _opened = true;
            _openNavigation();
          }
        },
        child: grabbable,
      ),
    );
  }

  Widget _tabRow(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (d) => _scrubTo(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _scrubTo(d.localPosition.dx),
      onHorizontalDragEnd: (_) => _endScrub(),
      onHorizontalDragCancel: _endScrub,
      child: Stack(
        children: [
          if (_hasActive)
            AnimatedBuilder(
              animation: _lens,
              builder: (context, _) {
                // The lens glides to the new tab: same size the whole way,
                // no stretch, no squash.
                final left = _inset + _lensPosition * _slot;
                return Positioned(
                  left: left,
                  top: _inset,
                  width: _slot,
                  height: _lensHeight,
                  // A soft fill, no outline: part of the capsule, not a
                  // sticker on it.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(_lensHeight / 2),
                    ),
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  SizedBox(width: _slot, child: _tab(context, _tabs[i])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedTab(BuildContext context) {
    final tab = _tabs[_activeIndex];
    final c = context.colors;
    return Tooltip(
      message: 'Show navigation',
      child: Semantics(
        button: true,
        label: '${tab.label}, show navigation',
        excludeSemantics: true,
        child: _Pressable(
          onTap: () => widget.onExpand?.call(),
          child: Center(child: Icon(tab.activeIcon, size: 24, color: c.accent)),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, _NavTab tab) {
    final scrubbing = _scrubIndex != null;
    final active = scrubbing
        ? _tabs[_scrubIndex!].id == tab.id
        : widget.currentTab == tab.id;
    final c = context.colors;
    return Tooltip(
      message: tab.label,
      child: Semantics(
        button: true,
        selected: active,
        label: tab.label,
        excludeSemantics: true,
        child: _Pressable(
          onTap: () {
            if (widget.currentTab != tab.id) HapticFeedback.selectionClick();
            widget.onTabChanged(tab.id);
          },
          child: SizedBox(
            height: _keySize,
            child: Center(
              child: AnimatedSwitcher(
                duration: AppMotion.duration(context, AppMotion.base),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Icon(
                  active ? tab.activeIcon : tab.icon,
                  key: ValueKey(active),
                  size: 24,
                  color: active ? c.accent : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted capsule: content scrolling underneath shows through, blurred.
class _Glass extends StatelessWidget {
  final Widget child;

  const _Glass({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(_MobileNavState._keySize / 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Light mode only. The glass is translucent, so a shadow painted
        // under it shows *through* it: in dark mode the black smudge
        // muddied the whole lower half of the capsule. Dark relies on the
        // hairline and a more solid tint instead.
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            // Tint first, so the blurred content reads through it…
            decoration: BoxDecoration(
              borderRadius: radius,
              color: c.surface.withValues(alpha: dark ? 0.86 : 0.74),
            ),
            child: DecoratedBox(
              // …then a lit top edge and hairline: what sells it as glass.
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.07 : 0.45),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.55],
                ),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.12)
                      : c.border.withValues(alpha: 0.9),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The dock's one solid-accent control, set apart from the tabs.
class _CreateKey extends StatelessWidget {
  final double size;
  final VoidCallback onCreate;

  const _CreateKey({required this.size, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: 'New note',
      child: Semantics(
        button: true,
        label: 'Create',
        excludeSemantics: true,
        child: _Pressable(
          onTap: () {
            HapticFeedback.lightImpact();
            onCreate();
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: c.accent,
              shape: BoxShape.circle,
              // Same rule as the glass capsule: a soft shadow in light mode,
              // none in dark (a black halo on a near-black page is a smudge).
              boxShadow: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Icon(Icons.add_rounded, size: 30, color: c.onAccent),
          ),
        ),
      ),
    );
  }
}

/// Tap target that dims slightly while pressed — feedback without any
/// size change.
class _Pressable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _Pressable({required this.onTap, required this.child});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: AppMotion.duration(context, AppMotion.fast),
        child: widget.child,
      ),
    );
  }
}
