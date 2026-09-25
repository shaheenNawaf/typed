import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/app_motion.dart';
import '../widgets/brand_mark.dart';

/// Signature for completing the introduction: the finance depth the user
/// picked and whether to keep the sample finance entries.
typedef OnOnboardingFinish =
    void Function({required bool includeSamples, required String financeMode});

/// First-launch introduction: what Typed is, how writing works, and how deep
/// the finance tracker should go. Shown once (and again from Settings >
/// "Replay introduction").
class OnboardingScreen extends StatefulWidget {
  final OnOnboardingFinish onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  String _financeMode = 'simple';
  bool _includeSamples = true;

  static const _pageCount = 4;

  bool get _isLast => _page == _pageCount - 1;

  void _finish() {
    widget.onFinish(includeSamples: _includeSamples, financeMode: _financeMode);
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: AppMotion.duration(context, AppMotion.page),
      curve: AppMotion.emphasized,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.escape): _finish,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PaperGridPainter(
                      lineColor: c.border.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: c.muted,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        child: const Text('Skip'),
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _controller,
                        onPageChanged: (index) => setState(() => _page = index),
                        children: [
                          _welcomePage(),
                          _writingPage(),
                          _financePage(),
                          _gettingAroundPage(),
                        ],
                      ),
                    ),
                    _buildFooter(c),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -- Page 1: welcome --------------------------------------------------------

  Widget _welcomePage() {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BrandMark(size: 64, fg: c.fg, accent: c.accent),
              const SizedBox(height: 24),
              Text(
                'Typed',
                style: TextStyle(
                  fontSize: AppType.t28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A quiet workspace for notes, tasks, and money.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.t15, height: 1.5, color: c.fg),
              ),
              const SizedBox(height: 8),
              Text(
                'Local-first and private — everything stays on this device. '
                'Export a backup any time from Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppType.t13_5, height: 1.5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Page 2: writing --------------------------------------------------------

  Widget _writingPage() {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Write the way you think',
                style: TextStyle(
                  fontSize: AppType.t22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Everything is Markdown under the hood — fast to type, '
                'clean to read.',
                style: TextStyle(fontSize: AppType.t13_5, height: 1.5, color: c.muted),
              ),
              const SizedBox(height: 24),
              _featureRow(
                c,
                Icons.bolt_outlined,
                'Slash commands',
                'Type / for headings, lists, tables, code, and links.',
              ),
              const SizedBox(height: 16),
              _featureRow(
                c,
                Icons.checklist_outlined,
                'Checklists',
                'Tick tasks from the note, the Tasks list, or your '
                    'home-screen widget.',
              ),
              const SizedBox(height: 16),
              _featureRow(
                c,
                Icons.tag,
                'Tags, pins & links',
                'Organize with #tags, pin what matters, and connect pages '
                    'with [[links]].',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(
    AppColors c,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.accentDim,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: c.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: AppType.t15,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: AppType.t12, height: 1.45, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -- Page 3: finance depth --------------------------------------------------

  Widget _financePage() {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track money your way',
                style: TextStyle(
                  fontSize: AppType.t22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A full finance tracker can feel like a lot. Pick how deep '
                'yours goes — you can switch anytime on the Finance page.',
                style: TextStyle(fontSize: AppType.t13_5, height: 1.5, color: c.muted),
              ),
              const SizedBox(height: 18),
              _modeCard(
                c,
                value: 'simple',
                title: 'Simple',
                subtitle:
                    'This month at a glance, with one-tap capture for '
                    'expenses and income.',
                badge: 'Recommended',
              ),
              const SizedBox(height: 10),
              _modeCard(
                c,
                value: 'advanced',
                title: 'Advanced',
                subtitle:
                    'Categories, budgets, trends, currency scopes, and CSV '
                    'export.',
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => setState(() => _includeSamples = !_includeSamples),
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _includeSamples,
                        onChanged: (value) =>
                            setState(() => _includeSamples = value ?? true),
                        activeColor: c.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Include sample finance entries',
                              style: TextStyle(
                                fontSize: AppType.t13_5,
                                fontWeight: FontWeight.w500,
                                color: c.fg,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'A demo expense and budget to explore with — '
                              'remove them later in Settings.',
                              style: TextStyle(
                                fontSize: AppType.t12,
                                height: 1.4,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gettingAroundPage() {
    final c = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Everything in reach',
                style: TextStyle(
                  fontSize: AppType.t22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: c.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A quick tour before you start — replay any time from Settings.',
                style: TextStyle(fontSize: AppType.t13_5, height: 1.5, color: c.muted),
              ),
              const SizedBox(height: 24),
              _featureRow(
                c,
                Icons.dashboard_outlined,
                'The dock',
                'Home, Notes, Finance and Tasks live in the bottom dock. '
                    'The + button creates anything.',
              ),
              const SizedBox(height: 16),
              _featureRow(
                c,
                Icons.visibility_outlined,
                'Preview & Edit',
                'Tap Preview to read a clean copy of a note; tap Edit to '
                    'change it.',
              ),
              const SizedBox(height: 16),
              _featureRow(
                c,
                Icons.code,
                'Raw mode',
                'Prefer the plain symbols? The Raw button in the toolbar '
                    'shows the exact Markdown.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard(
    AppColors c, {
    required String value,
    required String title,
    required String subtitle,
    String? badge,
  }) {
    final selected = _financeMode == value;
    return InkWell(
      onTap: () => setState(() => _financeMode = value),
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? c.accentDim : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(
            color: selected ? c.accent : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: AppType.t15,
                          fontWeight: FontWeight.w600,
                          color: selected ? c.accent : c.fg,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.listBg,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: AppType.t10,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: AppType.t12,
                      height: 1.45,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? c.accent : c.muted,
            ),
          ],
        ),
      ),
    );
  }

  // -- Footer -----------------------------------------------------------------

  Widget _buildFooter(AppColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Row(
        children: [
          Row(
            children: List.generate(_pageCount, (index) {
              return AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.base),
                curve: AppMotion.emphasized,
                margin: const EdgeInsets.only(right: 6),
                width: index == _page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _page ? c.accent : c.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _next,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.onAccent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isLast ? 'Get started' : 'Next',
                  style: const TextStyle(
                    fontSize: AppType.t13_5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!_isLast) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperGridPainter extends CustomPainter {
  final Color lineColor;

  _PaperGridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    const spacing = 24.0;

    double x = 0;
    while (x <= size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += spacing;
    }
    double y = 0;
    while (y <= size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += spacing;
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGridPainter old) =>
      old.lineColor != lineColor;
}
