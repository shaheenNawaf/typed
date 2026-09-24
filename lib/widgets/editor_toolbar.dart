import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_metrics.dart';
import 'table_picker_sheet.dart';

class EditorToolbar extends StatefulWidget {
  final ValueChanged<String> onInsertMD;
  final ValueChanged<String> onInsertLine;
  final void Function(int rows, int cols, TableAlign align) onInsertTable;
  final bool previewMode;
  final VoidCallback onTogglePreview;
  final int wordCount;
  final VoidCallback? onImagePick;

  const EditorToolbar({
    super.key,
    required this.onInsertMD,
    required this.onInsertLine,
    required this.onInsertTable,
    required this.previewMode,
    required this.onTogglePreview,
    required this.wordCount,
    this.onImagePick,
  });

  @override
  State<EditorToolbar> createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 1024;
    final horizontalPad = isMobile ? 20.0 : 32.0;

    final formatting = [
      _tbIcon(Icons.format_bold, () => widget.onInsertMD('**|**'), tooltip: 'Bold'),
      _tbIcon(Icons.format_italic, () => widget.onInsertMD('*|*'), tooltip: 'Italic'),
      _tbIcon(Icons.code, () => widget.onInsertMD('`|`'), tooltip: 'Inline code'),
      _tbIcon(Icons.format_strikethrough, () => widget.onInsertMD('~~|~~'), tooltip: 'Strikethrough'),
    ];

    final headings = [
      _tbText('H2', () => widget.onInsertLine('## '), tooltip: 'Heading 2'),
      _tbText('H3', () => widget.onInsertLine('### '), tooltip: 'Heading 3'),
      _tbIcon(Icons.link, () => widget.onInsertMD('[|](url)'), tooltip: 'Link'),
    ];

    final lists = [
      _tbIcon(Icons.format_list_bulleted, () => widget.onInsertLine('- '), tooltip: 'Bulleted list'),
      _tbIcon(Icons.check_box_outlined, () => widget.onInsertLine('- [ ] '), tooltip: 'Checklist'),
      _tbIcon(Icons.format_quote, () => widget.onInsertLine('> '), tooltip: 'Quote'),
    ];

    final extras = [
      if (widget.onImagePick != null)
        _tbIcon(Icons.add_a_photo_outlined, widget.onImagePick!, tooltip: 'Insert image'),
      _tbIcon(Icons.table_chart, () {
        TablePickerSheet.show(
          context,
          onInsert: (rows, cols, align) =>
              widget.onInsertTable(rows, cols, align),
        );
      }, tooltip: 'Insert table'),
      _tbIcon(Icons.help_outline, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ctrl+N New \u00b7 Ctrl+B Bold \u00b7 Ctrl+I Italic \u00b7 '
              'Use the link toolbar button \u00b7 Ctrl+S Save \u00b7 Esc Close',
            ),
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }, tooltip: 'Keyboard shortcuts'),
    ];

    final List<Widget> primaryRow;
    if (!widget.previewMode) {
      primaryRow = [
        ...formatting,
        _sep(),
        ...headings,
        _sep(),
        ...lists,
        _sep(),
        ...extras,
      ];
    } else {
      primaryRow = const <Widget>[];
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: 12,
        left: horizontalPad,
        right: horizontalPad,
      ),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
         child: AnimatedSize(
           duration: AppMotion.duration(context, AppMotion.base),
           curve: AppMotion.emphasized,
           child: Container(
             constraints: BoxConstraints(
               minHeight: 44,
               maxHeight: isMobile && _expanded ? 150 : 44,
             ),
             decoration: BoxDecoration(
               color: context.colors.surface,
               borderRadius: BorderRadius.circular(24),
               border: Border.all(color: context.colors.border.withAlpha(100)),
             ),
              child: isMobile
                  ? _buildMobile(primaryRow)
                  : _buildDesktop(primaryRow),
           ),
         ),
      ),
    );
  }

  Widget _buildDesktop(List<Widget> primaryRow) {
    return Row(
      children: [
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: primaryRow,
            ),
          ),
        ),
        _wordCountBadge(),
        const SizedBox(width: 4),
        _previewToggle(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMobile(List<Widget> primaryRow) {
    if (primaryRow.isEmpty) {
      return Row(
        children: [
          const Spacer(),
          _wordCountBadge(),
          const SizedBox(width: 4),
          _previewToggle(),
          const SizedBox(width: 4),
        ],
      );
    }
    return Row(
      children: [
        const SizedBox(width: 4),
        if (!_expanded)
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                _tbIcon(Icons.format_bold, () => widget.onInsertMD('**|**')),
                _tbIcon(Icons.format_italic, () => widget.onInsertMD('*|*')),
                _tbIcon(Icons.code, () => widget.onInsertMD('`|`')),
                _sep(),
                _tbIcon(Icons.format_list_bulleted, () => widget.onInsertLine('- ')),
                _tbIcon(Icons.check_box_outlined, () => widget.onInsertLine('- [ ] ')),
                _sep(),
                _tbText('H2', () => widget.onInsertLine('## ')),
                _tbText('H3', () => widget.onInsertLine('### ')),
              ],
            ),
          ),
        if (!_expanded) ...[
          _wordCountBadge(),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => setState(() => _expanded = true),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 32, height: 32,
              alignment: Alignment.center,
              child: Icon(Icons.more_horiz, size: 20, color: context.colors.muted),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (_expanded)
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ...primaryRow,
                  _sep(),
                  _previewToggle(),
                  const SizedBox(width: 4, height: 36),
                  InkWell(
                    onTap: () => setState(() => _expanded = false),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _wordCountBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.border.withAlpha(60),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Text('${widget.wordCount} w',
          style: TextStyle(
            fontSize: AppType.t11, fontFamily: context.colors.monoFontFamily,
            color: context.colors.muted, letterSpacing: 0.04,
          )),
    );
  }

  Widget _previewToggle() {
    return InkWell(
      onTap: widget.onTogglePreview,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.previewMode
              ? context.colors.accentDim
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(widget.previewMode ? 'Edit' : 'Preview',
          style: TextStyle(
            fontSize: AppType.t12, letterSpacing: 0.02,
            color: widget.previewMode
                ? context.colors.accent
                : context.colors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _tbIcon(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: context.colors.muted),
        ),
      ),
    );
  }

  Widget _tbText(String label, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 40, height: 40,
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontSize: AppType.t13_5, fontWeight: FontWeight.w700,
            color: context.colors.muted,
          )),
        ),
      ),
    );
  }

  Widget _sep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 1, height: 20,
        child: ColoredBox(color: context.colors.border.withAlpha(80)),
      ),
    );
  }
}
