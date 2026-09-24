import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';

class CommandPaletteAction {
  final String id;
  final String label;
  final String? description;
  final IconData icon;
  final String? shortcut;
  final VoidCallback onInvoke;

  /// Extra text matched by the filter but never rendered — lets page results
  /// be found by their full note content, like the note-list search.
  final String? searchText;

  const CommandPaletteAction({
    required this.id,
    required this.label,
    this.description,
    required this.icon,
    this.shortcut,
    required this.onInvoke,
    this.searchText,
  });
}

class CommandPalette extends StatefulWidget {
  final List<CommandPaletteAction> actions;
  final VoidCallback onDismiss;

  const CommandPalette({
    super.key,
    required this.actions,
    required this.onDismiss,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  int _selected = 0;

  List<CommandPaletteAction> get _filtered {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return widget.actions;
    return widget.actions.where((action) {
      final haystack = [
        action.label,
        action.description ?? '',
        action.id,
        // Bounded so a huge note cannot stall filtering on every keystroke.
        if (action.searchText != null)
          action.searchText!.substring(0, action.searchText!.length.clamp(0, 5000)),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(_resetSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.removeListener(_resetSelection);
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _resetSelection() => setState(() => _selected = 0);

  void _move(int delta) {
    final count = _filtered.length;
    if (count == 0) return;
    setState(() => _selected = (_selected + delta + count) % count);
  }

  void _invokeSelected() {
    final actions = _filtered;
    if (actions.isEmpty) return;
    final action = actions[_selected.clamp(0, actions.length - 1)];
    widget.onDismiss();
    action.onInvoke();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = _filtered;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveUpIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _InvokeIntent(),
        SingleActivator(LogicalKeyboardKey.tab): _InvokeIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
      },
      child: Actions(
        actions: {
          _MoveDownIntent: CallbackAction<_MoveDownIntent>(
            onInvoke: (_) => _move(1),
          ),
          _MoveUpIntent: CallbackAction<_MoveUpIntent>(
            onInvoke: (_) => _move(-1),
          ),
          _InvokeIntent: CallbackAction<_InvokeIntent>(
            onInvoke: (_) => _invokeSelected(),
          ),
          _DismissIntent: CallbackAction<_DismissIntent>(
            onInvoke: (_) => widget.onDismiss(),
          ),
        },
        child: Focus(
          focusNode: _focus,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.duration(context, AppMotion.slow),
              curve: AppMotion.decelerate,
              builder: (context, t, _) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: widget.onDismiss,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.28 * t),
                        ),
                      ),
                    ),
                    Center(
                      child: ConstrainedBox(
                        // Bound to the available height too: with the keyboard
                        // up on a phone the fixed-size internals used to
                        // overflow the screen.
                        constraints: BoxConstraints(
                          maxWidth: 600,
                          maxHeight:
                              MediaQuery.sizeOf(context).height * 0.75,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Transform.translate(
                            offset: Offset(0, 10 * (1 - t)),
                            child: Transform.scale(
                              scale: 0.97 + 0.03 * t,
                              child: Opacity(
                                opacity: t,
                                child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          border: Border.all(color: c.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 30,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                10,
                              ),
                              child: TextField(
                                controller: _query,
                                autofocus: true,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Search actions and pages...',
                                  hintStyle: TextStyle(color: c.muted),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: c.muted,
                                  ),
                                  suffixText: 'ESC',
                                  suffixStyle: TextStyle(
                                    color: c.muted,
                                    fontSize: AppType.t10,
                                    fontFamily: c.monoFontFamily,
                                  ),
                                ),
                                style: TextStyle(color: c.fg),
                              ),
                            ),
                            Divider(height: 1, color: c.border),
                            if (actions.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No matching actions',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: c.muted),
                                ),
                              )
                            else
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 380,
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                  padding: const EdgeInsets.all(8),
                                  itemCount: actions.length,
                                  itemBuilder: (context, index) {
                                    final action = actions[index];
                                    final selected = index == _selected;
                                    return InkWell(
                                      onTap: () {
                                        widget.onDismiss();
                                        action.onInvoke();
                                      },
                                      borderRadius: BorderRadius.circular(AppRadius.card),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? c.accentDim
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              action.icon,
                                              size: 18,
                                              color: selected
                                                  ? c.accent
                                                  : c.muted,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    action.label,
                                                    style: TextStyle(
                                                      color: c.fg,
                                                      fontSize: AppType.t13_5,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  if (action.description !=
                                                      null)
                                                    Text(
                                                      action.description!,
                                                      style: TextStyle(
                                                        color: c.muted,
                                                        fontSize: AppType.t11,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (action.shortcut != null)
                                              Text(
                                                action.shortcut!,
                                                style: TextStyle(
                                                  color: c.muted,
                                                  fontSize: AppType.t10,
                                                  fontFamily: c.monoFontFamily,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                   },
                                 ),
                               ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  ),
),
),
),
);
  }
}

class _MoveDownIntent extends Intent {
  const _MoveDownIntent();
}

class _MoveUpIntent extends Intent {
  const _MoveUpIntent();
}

class _InvokeIntent extends Intent {
  const _InvokeIntent();
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}
