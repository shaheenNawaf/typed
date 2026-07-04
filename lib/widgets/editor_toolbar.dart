import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'table_picker_sheet.dart';

class EditorToolbar extends StatefulWidget {
  final ValueChanged<String> onInsertMD;
  final ValueChanged<String> onInsertLine;
  final void Function(int rows, int cols, TableAlign align) onInsertTable;
  final bool previewMode;
  final VoidCallback onTogglePreview;
  final int wordCount;
  final ValueChanged<double>? onSizeChanged;
  final VoidCallback? onImagePick;

  const EditorToolbar({
    super.key,
    required this.onInsertMD,
    required this.onInsertLine,
    required this.onInsertTable,
    required this.previewMode,
    required this.onTogglePreview,
    required this.wordCount,
    this.onSizeChanged,
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
    final iconSize = 20.0;
    final btnSize = 36.0;
    final horizontalPad = isMobile ? 20.0 : 32.0;

    final formatting = [
      _tbIcon(Icons.format_bold, () => widget.onInsertMD('**|**')),
      _tbIcon(Icons.format_italic, () => widget.onInsertMD('*|*')),
      _tbIcon(Icons.code, () => widget.onInsertMD('`|`')),
      _tbIcon(Icons.format_strikethrough, () => widget.onInsertMD('~~|~~')),
    ];

    final headings = [
      _tbText('H2', () => widget.onInsertLine('## ')),
      _tbText('H3', () => widget.onInsertLine('### ')),
      _tbIcon(Icons.link, () => widget.onInsertMD('[|](url)')),
    ];

    final lists = [
      _tbIcon(Icons.format_list_bulleted, () => widget.onInsertLine('- ')),
      _tbIcon(Icons.check_box_outlined, () => widget.onInsertLine('- [ ] ')),
      _tbIcon(Icons.format_quote, () => widget.onInsertLine('> ')),
    ];

    final extras = [
      if (widget.onImagePick != null)
        _tbIcon(Icons.add_a_photo_outlined, widget.onImagePick!),
      _tbIcon(Icons.table_chart, () {
        TablePickerSheet.show(
          context,
          onInsert: (rows, cols, align) =>
              widget.onInsertTable(rows, cols, align),
        );
      }),
      _tbIcon(Icons.help_outline, () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ctrl+N New \u00b7 Ctrl+B Bold \u00b7 Ctrl+I Italic \u00b7 '
              'Ctrl+K Link \u00b7 Ctrl+S Save \u00b7 Esc Close',
            ),
            duration: Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }),
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
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border.withAlpha(100)),
          ),
          child: isMobile
              ? _buildMobile(primaryRow, iconSize, btnSize)
              : _buildDesktop(primaryRow, iconSize, btnSize),
        ),
      ),
    );
  }

  Widget _buildDesktop(List<Widget> primaryRow, double iconSize, double btnSize) {
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

  Widget _buildMobile(List<Widget> primaryRow, double iconSize, double btnSize) {
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
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                ...primaryRow,
                _sep(),
                _previewToggle(),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => setState(() => _expanded = false),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 32, height: 32,
                    alignment: Alignment.center,
                    child: Icon(Icons.close, size: 18, color: context.colors.muted),
                  ),
                ),
              ],
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('${widget.wordCount} w',
          style: TextStyle(
            fontSize: 11, fontFamily: context.colors.monoFontFamily,
            color: context.colors.muted, letterSpacing: 0.04,
          )),
    );
  }

  Widget _previewToggle() {
    return InkWell(
      onTap: widget.onTogglePreview,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: widget.previewMode
              ? context.colors.accentDim
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(widget.previewMode ? 'Edit' : 'Preview',
          style: TextStyle(
            fontSize: 12, letterSpacing: 0.02,
            color: widget.previewMode
                ? context.colors.accent
                : context.colors.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _tbIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: context.colors.muted),
      ),
    );
  }

  Widget _tbText(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700,
          color: context.colors.muted,
        )),
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
