import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import '../models/money_entry.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../theme/fonts.dart';
import '../theme/theme_controller.dart';
import '../utils/date_format.dart';
import '../utils/finance_utils.dart';
import '../utils/id.dart';
import '../utils/image_paths.dart';
import '../utils/markdown_display.dart';
import '../utils/markdown_highlight.dart';
import '../utils/slash_commands.dart';
import 'editor_toolbar.dart';
import 'entry_sheet.dart';
import 'image_picker_sheet.dart';
import 'table_picker_sheet.dart';

class Editor extends StatefulWidget {
  final Note? note;
  final ValueChanged<String> onTitleChange;
  final ValueChanged<String> onContentChange;
  final ValueChanged<String> onImageAdded;
  final bool previewMode;
  final VoidCallback onTogglePreview;
  final List<Note> allNotes;
  final void Function(String noteId) onOpenNote;
  final ValueChanged<String> onTypeChange;
  final ValueChanged<String> onCurrencyChange;
  final ValueChanged<List<MoneyEntry>> onAmountsChange;
  final ValueChanged<List<String>> onTagsChange;
  final void Function(Note)? onArchive;
  final void Function(Note)? onDelete;
  final void Function(Note)? onTogglePin;
  final List<String> customCategories;
  final List<String> recentCategories;
  final void Function(String)? onCategoryUsed;
  final VoidCallback? onSaveNow;
  final VoidCallback? onToggleContext;
  final bool contextPanelOpen;

  /// 'idle' | 'saving' | 'saved' — surfaces the otherwise-invisible
  /// debounced autosave.
  final String saveState;

  const Editor({
    super.key,
    required this.note,
    required this.onTitleChange,
    required this.onContentChange,
    required this.onImageAdded,
    required this.previewMode,
    required this.onTogglePreview,
    required this.allNotes,
    required this.onOpenNote,
    required this.onTypeChange,
    required this.onCurrencyChange,
    required this.onAmountsChange,
    required this.onTagsChange,
    this.onArchive,
    this.onDelete,
    this.onTogglePin,
    this.customCategories = const [],
    this.recentCategories = const [],
    this.onCategoryUsed,
    this.onSaveNow,
    this.onToggleContext,
    this.contextPanelOpen = false,
    this.saveState = 'idle',
  });

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  final ScrollController _bodyScroll = ScrollController();
  double _bodyScrollOffset = 0;
  late TextEditingController _newTagCtrl;
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _newTagFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  bool _addingTag = false;
  final ImagePicker _picker = ImagePicker();
  List<Note> _linkSuggestions = [];
  List<SlashCommandDefinition> _slashSuggestions = [];
  int _slashSelectedIndex = 0;
  SlashToken? _slashToken;
  final TextRecognizer? _textRecognizer = kIsWeb
      ? null
      : TextRecognizer(script: TextRecognitionScript.latin);
  int? _checklistEditIdx;
  final TextEditingController _checklistAddCtrl = TextEditingController();
  final TextEditingController _checklistEditCtrl = TextEditingController();
  final FocusNode _checklistEditFocus = FocusNode();
  int? _dismissedSlashStart;
  String? _dismissedSlashText;

  double get _horizontalPad {
    return MediaQuery.of(context).size.width >= 1024 ? 32.0 : 20.0;
  }

  /// The Settings font choice must reach the writing surface; this replaces
  /// the DM Sans this file previously hardcoded into every style.
  FontOption get _fontOption =>
      ThemeController.instance?.font ?? kFontOptions.first;

  TextStyle _editorFont({
    bool display = false,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    final font = _fontOption;
    if (!font.usesGoogleFonts) {
      return TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }
    return GoogleFonts.getFont(
      display
          ? (font.displayFontFamily ?? font.uiFontFamily)
          : font.uiFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.note?.content ?? '');
    _newTagCtrl = TextEditingController();
    _contentCtrl.addListener(_onContentChange);
    _bodyScroll.addListener(_onBodyScroll);
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onContentChange);
    _bodyScroll.dispose();
    _titleFocus.dispose();
    _newTagFocus.dispose();
    _contentFocus.dispose();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _newTagCtrl.dispose();
    _checklistAddCtrl.dispose();
    _checklistEditCtrl.dispose();
    _checklistEditFocus.dispose();
    try {
      _textRecognizer?.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didUpdateWidget(Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.note?.id != oldWidget.note?.id) {
      _titleCtrl.text = widget.note?.title ?? '';
      _contentCtrl.text = widget.note?.content ?? '';
      // Per-note transient UI must not bleed into the next note.
      _addingTag = false;
      _newTagCtrl.clear();
      _checklistEditIdx = null;
      _linkSuggestions = [];
      _slashSuggestions = [];
      _slashToken = null;
      _dismissedSlashStart = null;
      return;
    }
    // Same note, but its content changed outside this editor (e.g. a
    // checklist item toggled from the note list while the note is open on
    // desktop). Resync so the next local edit does not overwrite the
    // external change with stale controller text. A focused field wins —
    // the user's in-flight typing is authoritative over a background change.
    final note = widget.note;
    if (note == null) return;
    if (!_titleFocus.hasFocus && _titleCtrl.text != note.title) {
      _titleCtrl.value = TextEditingValue(text: note.title);
    }
    if (!_contentFocus.hasFocus && _contentCtrl.text != note.content) {
      final offset =
          _contentCtrl.selection.baseOffset.clamp(0, note.content.length);
      _contentCtrl.value = TextEditingValue(
        text: note.content,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
  }

  int get _wordCount {
    final text = _contentCtrl.text.trim();
    return text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
  }

  void _onContentChange() {
    if (!mounted) return;
    _updateSlashSuggestions();
    _updateLinkSuggestions();
  }

  void _updateLinkSuggestions() {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_linkSuggestions.isNotEmpty) {
        setState(() => _linkSuggestions = []);
      }
      return;
    }
    final cursor = sel.baseOffset;
    int lastOpen = -1;
    for (int i = cursor - 2; i >= 0; i--) {
      if (text[i] == '[' && text[i + 1] == '[') {
        lastOpen = i;
        break;
      }
      if (text[i] == ']' || text[i] == '\n' || text[i] == '|') {
        lastOpen = -1;
        break;
      }
    }
    if (lastOpen == -1) {
      if (_linkSuggestions.isNotEmpty) {
        setState(() => _linkSuggestions = []);
      }
      return;
    }
    final query = text.substring(lastOpen + 2, cursor);
    if (query.length > 50 || query.contains('\n')) {
      if (_linkSuggestions.isNotEmpty) {
        setState(() => _linkSuggestions = []);
      }
      return;
    }
    final q = query.toLowerCase();
    final matches = widget.allNotes
        .where(
          (n) =>
              !n.isArchived &&
              !n.isDeleted &&
              n.id != widget.note?.id &&
              n.title.toLowerCase().contains(q),
        )
        .take(5)
        .toList();
    setState(() => _linkSuggestions = matches);
  }

  void _updateSlashSuggestions() {
    final selection = _contentCtrl.selection;
    final note = widget.note;
    if (widget.previewMode ||
        note == null ||
        note.type == 'expense' ||
        note.type == 'income' ||
        !selection.isValid ||
        !selection.isCollapsed) {
      if (_slashSuggestions.isNotEmpty || _slashToken != null) {
        setState(() {
          _slashSuggestions = [];
          _slashToken = null;
        });
      }
      return;
    }

    final token = activeSlashToken(_contentCtrl.text, selection.baseOffset);
    if (token == null) {
      if (_slashSuggestions.isNotEmpty || _slashToken != null) {
        setState(() {
          _slashSuggestions = [];
          _slashToken = null;
        });
      }
      return;
    }
    // Sticky dismissal: while the exact token that was escaped is still on
    // screen, keep the menu hidden instead of popping it back up on the
    // next keystroke.
    if (token.start == _dismissedSlashStart &&
        _dismissedSlashText != null &&
        '/${token.query}'.startsWith(_dismissedSlashText!)) {
      if (_slashSuggestions.isNotEmpty) {
        setState(() => _slashSuggestions = []);
      }
      _slashToken = token;
      return;
    }
    _dismissedSlashStart = null;
    _dismissedSlashText = null;

    final matches = filterSlashCommands(token.query);
    setState(() {
      _slashToken = token;
      _slashSuggestions = matches;
      _slashSelectedIndex = 0;
    });
  }

  KeyEventResult _handleEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _slashSuggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _slashSelectedIndex =
            (_slashSelectedIndex + 1) % _slashSuggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _slashSelectedIndex =
            (_slashSelectedIndex - 1 + _slashSuggestions.length) %
                _slashSuggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _insertSlashCommand(_slashSuggestions[_slashSelectedIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _dismissedSlashStart = _slashToken?.start;
        _dismissedSlashText = _slashToken == null
            ? null
            : '/${_slashToken!.query}';
        _slashSuggestions = [];
        _slashToken = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _insertSlashCommand(SlashCommandDefinition command) {
    final token = _slashToken;
    if (token == null) return;
    final replacement = command.insertion;
    final newText = replaceSlashToken(_contentCtrl.text, token, replacement);
    _contentCtrl.text = newText;
    final offset = token.start + replacement.length;
    _contentCtrl.selection = TextSelection.collapsed(offset: offset);
    _syncContent();
    setState(() {
      _slashSuggestions = [];
      _slashToken = null;
    });
    if (command.id == 'table') {
      TablePickerSheet.show(
        context,
        onInsert: (rows, cols, align) => _insertTable(rows, cols, align),
      );
    } else {
      _contentFocus.requestFocus();
    }
  }

  void _insertLink(Note note) {
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    int lastOpen = -1;
    for (int i = cursor - 2; i >= 0; i--) {
      if (text[i] == '[' && text[i + 1] == '[') {
        lastOpen = i;
        break;
      }
    }
    if (lastOpen == -1) return;
    final before = text.substring(0, lastOpen);
    final after = text.substring(cursor);
    // ponytail: id-encoded link so renames don't break it.
    // Syntax: [[id|title]] — rendered as [title](#note:id) in preview.
    final insertion = '[[${note.id}|${note.title}]]';
    final newText = '$before$insertion$after';
    _contentCtrl.text = newText;
    _contentCtrl.selection = TextSelection.collapsed(
      offset: before.length + insertion.length,
    );
    _syncContent();
    setState(() => _linkSuggestions = []);
  }

  String _renderedContent() {
    final text = _contentCtrl.text;
    final byTitle = <String, String>{
      for (final n in widget.allNotes) n.title: n.id,
    };
    // First pass: resolve [[id|title]] (new syntax)
    var rendered = text.replaceAllMapped(
      RegExp(r'\[\[([^\]\n|]+)\|([^\]\n]+)\]\]'),
      (m) {
        final id = m.group(1)?.trim() ?? '';
        final title = m.group(2)?.trim() ?? '';
        return '[$title](#note:$id)';
      },
    );
    // Second pass: resolve [[title]] (old syntax, backward compat)
    rendered = rendered.replaceAllMapped(RegExp(r'\[\[([^\]\n|]+)\]\]'), (m) {
      final title = m.group(1)?.trim() ?? '';
      final id = byTitle[title];
      if (id == null) return m.group(0) ?? '';
      return '[$title](#note:$id)';
    });
    final note = widget.note;
    if (note != null && note.type != 'text' && note.amounts.isNotEmpty) {
      rendered = '$rendered\n\n${_entriesMarkdown(note)}';
    }
    return rendered;
  }

  String _entriesMarkdown(Note note) {
    final header = note.type == 'income' ? '## Income' : '## Expenses';
    final sorted = note.amounts.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final currencies = sorted.map((e) => e.currency ?? note.currency).toSet();
    final mixed = currencies.length > 1;

    final rows = StringBuffer();
    if (mixed) {
      rows.write(
        '| Date | Category | Currency | Amount |\n| --- | --- | --- | --- |\n',
      );
    } else {
      rows.write('| Date | Category | Amount |\n| --- | --- | --- |\n');
    }

    final totals = <String?, int>{};
    for (final e in sorted) {
      final cur = e.currency ?? note.currency;
      final sym = currencySymbol(cur);
      if (mixed) {
        rows.writeln(
          '| ${shortDate(e.date)} | ${e.category} | $cur | $sym${formatMinor(e.amount, cur)} |',
        );
      } else {
        rows.writeln(
          '| ${shortDate(e.date)} | ${e.category} | $sym${formatMinor(e.amount, cur)} |',
        );
      }
      totals[cur] = (totals[cur] ?? 0) + e.amount;
    }

    if (mixed) {
      for (final t in totals.entries) {
        rows.writeln(
          '| **Total (${t.key})** | | | **${currencySymbol(t.key)}${formatMinor(t.value, t.key)}** |',
        );
      }
    } else {
      final total = totals.values.fold<int>(0, (a, b) => a + b);
      final cur = note.currency;
      rows.write(
        '| **Total** | | **${currencySymbol(cur)}${formatMinor(total, cur)}** |',
      );
    }

    return '$header\n\n$rows';
  }

  void _setType(String type) {
    if (widget.note?.type == type) return;
    widget.onTypeChange(type);
  }

  void _setCurrency(String currency) {
    if (widget.note?.currency == currency) return;
    widget.onCurrencyChange(currency);
  }

  void _addOrUpdateEntry(MoneyEntry entry) {
    final note = widget.note;
    if (note == null) return;
    final list = note.amounts.toList();
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      list[idx] = entry;
    } else {
      list.add(entry);
    }
    list.sort((a, b) => b.date.compareTo(a.date));
    widget.onAmountsChange(list);
  }

  void _removeEntry(String entryId) {
    final note = widget.note;
    if (note == null) return;
    final list = note.amounts.where((e) => e.id != entryId).toList();
    widget.onAmountsChange(list);
  }

  /// A fresh controller reports an invalid selection (offset -1); inserting
  /// via the toolbar before ever focusing the body would crash substring.
  TextSelection get _bodySelection {
    final sel = _contentCtrl.selection;
    return sel.isValid && sel.start >= 0 && sel.end >= 0
        ? sel
        : TextSelection.collapsed(offset: _contentCtrl.text.length);
  }

  void _insertMD(String pattern) {
    final parts = pattern.split('|');
    final before = parts[0];
    final after = parts.length > 1 ? parts[1] : '';
    final selStart = _bodySelection.start;
    final selEnd = _bodySelection.end;
    final sel = _contentCtrl.text.substring(selStart, selEnd);

    final newText =
        _contentCtrl.text.substring(0, selStart) +
        before +
        sel +
        after +
        _contentCtrl.text.substring(selEnd);
    _contentCtrl.text = newText;
    _contentCtrl.selection = TextSelection.collapsed(
      offset: selStart + before.length,
    );
    _syncContent();
  }

  void _insertLine(String prefix) {
    final selStart = _bodySelection.start;
    final lastNewline = _contentCtrl.text.lastIndexOf('\n', selStart - 1);
    final lineStart = lastNewline + 1;

    final newText =
        _contentCtrl.text.substring(0, lineStart) +
        prefix +
        _contentCtrl.text.substring(lineStart);
    _contentCtrl.text = newText;
    _contentCtrl.selection = TextSelection.collapsed(
      offset: lineStart + prefix.length,
    );
    _syncContent();
  }

  String _tableSep(TableAlign a) {
    switch (a) {
      case TableAlign.left:
        return ':---';
      case TableAlign.center:
        return ':---:';
      case TableAlign.right:
        return '---:';
    }
  }

  void _insertTable(int rows, int cols, TableAlign align) {
    final widths = List.generate(cols, (i) => 'Col ${i + 1}'.length);
    for (var i = 0; i < cols; i++) {
      if (widths[i] < 5) widths[i] = 5;
    }
    final sepTemplate = _tableSep(align);
    String pad(String s, int w) {
      if (s.length >= w) return s;
      final pad = w - s.length;
      return s + (' ' * pad);
    }

    final headerCells = List.generate(
      cols,
      (i) => pad('Col ${i + 1}', widths[i]),
    ).join(' | ');
    final sepCells = List.generate(
      cols,
      (i) => sepTemplate.padRight(widths[i]),
    ).join(' | ');
    final bodyCells = List.generate(rows, (_) {
      final cells = List.generate(
        cols,
        (i) => ' '.padRight(widths[i]),
      ).join(' | ');
      return '| $cells |';
    }).join('\n');

    final table = '\n| $headerCells |\n| $sepCells |\n$bodyCells\n';
    final cur = _contentCtrl.text;
    final needsLeadingNewline = cur.isNotEmpty && !cur.endsWith('\n');
    final insertion = needsLeadingNewline ? '\n$table' : table;

    final selStart = _bodySelection.start;
    final newText =
        cur.substring(0, selStart) + insertion + cur.substring(selStart);
    _contentCtrl.text = newText;
    _contentCtrl.selection = TextSelection.collapsed(
      offset: selStart + insertion.length,
    );
    _syncContent();
  }

  void _syncContent() {
    // Rebuild so the word count and live preview refresh after programmatic
    // edits (toolbar, slash commands), which fire the controller listener
    // but not a widget rebuild.
    if (mounted) setState(() {});
    widget.onTitleChange(_titleCtrl.text);
    widget.onContentChange(_contentCtrl.text);
  }

  void _onBodyScroll() {
    if (!mounted) return;
    final offset = _bodyScroll.offset;
    if (offset != _bodyScrollOffset) {
      setState(() => _bodyScrollOffset = offset);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Downscale in the picker on web: the result is embedded into the
        // note as a data URI (localStorage has a hard quota), so oversized
        // photos must never reach storage.
        maxWidth: kIsWeb ? 1600 : null,
        maxHeight: kIsWeb ? 1600 : null,
        imageQuality: kIsWeb ? 75 : null,
      );
      if (picked == null) return;
      await _saveAndInsert(picked);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: kIsWeb ? 1600 : null,
        maxHeight: kIsWeb ? 1600 : null,
        imageQuality: kIsWeb ? 75 : null,
      );
      if (picked == null) return;
      await _saveAndInsert(picked);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _saveAndInsert(XFile picked) async {
    final noteId = widget.note?.id;
    if (noteId == null) return;

    if (kIsWeb) {
      final bytes = await picked.readAsBytes();
      // Web persistence is localStorage-backed (~5 MB shared across all
      // keys); one large base64 blob can push every future save over quota.
      // 1 MB raw is ~1.4 MB as base64 — a deliberate safety ceiling.
      const webMaxImageBytes = 1 << 20;
      if (bytes.length > webMaxImageBytes) {
        _showError(
          'Image is too large for browser storage (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Choose one under 1 MB.',
        );
        return;
      }
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpeg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      final prefix =
          _contentCtrl.text.isEmpty || _contentCtrl.text.endsWith('\n\n')
          ? ''
          : '\n\n';
      _contentCtrl.text = '${_contentCtrl.text}$prefix![image]($dataUri)\n';
      _contentCtrl.selection = TextSelection.collapsed(
        offset: _contentCtrl.text.length,
      );
      _syncContent();
      // Do NOT add the data URI to imagePaths: the markdown above already
      // carries the full base64, and duplicating it doubles storage cost.
      return;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${docsDir.path}/images/$noteId');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final imageId = generateId('img');
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
    final dest = File('${imagesDir.path}/$imageId.$ext');
    await File(picked.path).copy(dest.path);

    // Insert image markdown at the end of the content
    final prefix =
        _contentCtrl.text.isEmpty || _contentCtrl.text.endsWith('\n\n')
        ? ''
        : '\n\n';
    final imageMarkdown = '$prefix![image](${dest.path})\n';
    _contentCtrl.text = _contentCtrl.text + imageMarkdown;
    _contentCtrl.selection = TextSelection.collapsed(
      offset: _contentCtrl.text.length,
    );
    _syncContent();
    widget.onImageAdded(dest.path);

    // Run OCR on the saved image in the background (mobile only)
    if (!kIsWeb) {
      unawaited(_runOcr(dest.path));
    }
  }

  Future<void> _runOcr(String imagePath) async {
    if (!mounted || kIsWeb || _textRecognizer == null) return;
    final sourceNoteId = widget.note?.id;
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await _textRecognizer.processImage(inputImage);
      if (!mounted) return;
      final text = result.text.trim();
      if (text.isNotEmpty) {
        // Count exactly what Append will insert (same filter), so the
        // snackbar number matches reality.
        final appendable = text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.length > 2)
            .toList();
        if (appendable.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Extracted ${appendable.length} lines from image'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Append',
                onPressed: () {
                  // Do not splice the scanned text into a different note if
                  // the user switched while the snackbar was up.
                  if (!mounted || widget.note?.id != sourceNoteId) return;
                  final quoted =
                      appendable.map((l) => '> $l').join('\n');
                  final addition = '\n$quoted\n';
                  _contentCtrl.text = _contentCtrl.text + addition;
                  _contentCtrl.selection = TextSelection.collapsed(
                    offset: _contentCtrl.text.length,
                  );
                  _syncContent();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not read text from the image: $e'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Image error: $e')));
  }

  void _openImagePicker() {
    ImagePickerSheet.show(
      context,
      onGallery: _pickFromGallery,
      onCamera: _pickFromCamera,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.note == null) return _emptyState();

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            _insertMD('**|**'),
        SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _insertMD('**|**'),
        SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            _insertMD('*|*'),
        SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _insertMD('*|*'),
        SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          _syncContent();
          widget.onSaveNow?.call();
        },
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          _syncContent();
          widget.onSaveNow?.call();
        },
      },
      child: Container(
        color: context.colors.bg,
        child: Column(
          children: [
            _buildTitleBar(),
            if (widget.note != null &&
                widget.note!.type != 'expense' &&
                widget.note!.type != 'income')
              _buildTagBar(),
            if (widget.note != null &&
                (widget.note!.type == 'expense' ||
                    widget.note!.type == 'income'))
              _buildFinanceContent(),
            Expanded(
              child: widget.note != null && widget.note!.type == 'todo'
                  ? _buildChecklistPanel()
                  : _buildBody(),
            ),
            EditorToolbar(
              onInsertMD: (p) => _insertMD(p),
              onInsertLine: (p) => _insertLine(p),
              onInsertTable: (rows, cols, align) =>
                  _insertTable(rows, cols, align),
              previewMode: widget.previewMode,
              onTogglePreview: widget.onTogglePreview,
              wordCount: _wordCount,
              onImagePick: _openImagePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    final note = widget.note;
    final isFinance =
        note != null && (note.type == 'expense' || note.type == 'income');
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.fromLTRB(_horizontalPad, 14, _horizontalPad, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _titleCtrl,
              focusNode: _titleFocus,
              onChanged: (_) => _syncContent(),
              style: _editorFont(
                display: true,
                fontSize: AppType.t22,
                fontWeight: FontWeight.w600,
                color: context.colors.fg,
                height: 1.2,
              ),
              decoration: InputDecoration(
                hintText: 'Note title...',
                hintStyle: TextStyle(color: context.colors.muted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (note != null) ...[
            if (widget.saveState != 'idle')
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 6),
                child: Text(
                  widget.saveState == 'saving' ? 'Saving…' : 'Saved',
                  style: TextStyle(fontSize: AppType.t11, color: context.colors.muted),
                ),
              ),
            if (!isMobile) ...[
              const SizedBox(width: 8),
              _TypeDropdown(value: note.type, onChanged: _setType),
              if (isFinance) ...[
                const SizedBox(width: 8),
                _CurrencyDropdown(
                  value: note.currency ?? 'PHP',
                  onChanged: _setCurrency,
                ),
              ],
            ],
          ],
          if (note != null &&
              (widget.onArchive != null || widget.onTogglePin != null))
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_horiz,
                size: 20,
                color: context.colors.muted,
              ),
              tooltip: 'Note actions',
              position: PopupMenuPosition.under,
              onSelected: (action) {
                switch (action) {
                  case 'pin':
                    widget.onTogglePin?.call(note);
                  case 'archive':
                    widget.onArchive?.call(note);
                  case 'delete':
                    widget.onDelete?.call(note);
                  case 'type:text':
                    _setType('text');
                  case 'type:todo':
                    _setType('todo');
                  case 'type:expense':
                    _setType('expense');
                  case 'type:income':
                    _setType('income');
                  case 'currency:PHP':
                    _setCurrency('PHP');
                  case 'currency:USD':
                    _setCurrency('USD');
                  case 'currency:EUR':
                    _setCurrency('EUR');
                  case 'currency:GBP':
                    _setCurrency('GBP');
                  case 'currency:JPY':
                    _setCurrency('JPY');
                  case 'currency:INR':
                    _setCurrency('INR');
                }
              },
              itemBuilder: (_) {
                final isMobile2 = MediaQuery.of(context).size.width < 600;
                final items = <PopupMenuEntry<String>>[];
                items.add(
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(
                          note.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(note.isPinned ? 'Unpin' : 'Pin'),
                      ],
                    ),
                  ),
                );
                items.add(
                  PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        const Icon(Icons.archive_outlined, size: 18),
                        const SizedBox(width: 8),
                        const Text('Archive'),
                      ],
                    ),
                  ),
                );
                if (isMobile2) {
                  items.add(const PopupMenuDivider());
                  items.add(
                    PopupMenuItem(
                      value: 'type:text',
                      child: Row(
                        children: [
                          const Icon(Icons.article_outlined, size: 18),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Text(
                                'Type: ',
                                style: TextStyle(color: context.colors.muted),
                              ),
                              const Text('Text'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  items.add(
                    PopupMenuItem(
                      value: 'type:todo',
                      child: Row(
                        children: [
                          Icon(
                            Icons.checklist_outlined,
                            size: 18,
                            color: context.colors.accent,
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Text(
                                'Type: ',
                                style: TextStyle(color: context.colors.muted),
                              ),
                              const Text('Todo'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  items.add(
                    PopupMenuItem(
                      value: 'type:expense',
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_downward,
                            size: 18,
                            color: context.colors.destructive,
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Text(
                                'Type: ',
                                style: TextStyle(color: context.colors.muted),
                              ),
                              const Text('Expense'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  items.add(
                    PopupMenuItem(
                      value: 'type:income',
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_upward,
                            size: 18,
                            color: context.colors.income,
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              Text(
                                'Type: ',
                                style: TextStyle(color: context.colors.muted),
                              ),
                              const Text('Income'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  if (isFinance) {
                    items.add(const PopupMenuDivider());
                    for (final c in _CurrencyDropdown.currencies) {
                      items.add(
                        PopupMenuItem(
                          value: 'currency:$c',
                          child: Row(
                            children: [
                              const Icon(Icons.attach_money, size: 18),
                              const SizedBox(width: 8),
                              Row(
                                children: [
                                  Text(
                                    'Currency: ',
                                    style: TextStyle(
                                      color: context.colors.muted,
                                    ),
                                  ),
                                  Text(c),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  }
                }
                items.add(const PopupMenuDivider());
                items.add(
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: context.colors.destructive,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: context.colors.destructive),
                        ),
                      ],
                    ),
                  ),
                );
                return items;
              },
            ),
          if (widget.onToggleContext != null)
            IconButton(
              onPressed: widget.onToggleContext,
              tooltip: widget.contextPanelOpen
                  ? 'Hide page details'
                  : 'Show page details',
              icon: Icon(
                widget.contextPanelOpen
                    ? Icons.view_sidebar
                    : Icons.view_sidebar_outlined,
                size: 19,
                color: widget.contextPanelOpen
                    ? context.colors.accent
                    : context.colors.muted,
              ),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildFinanceContent() {
    final note = widget.note;
    if (note == null) return const SizedBox.shrink();

    final currencyCounts = <String, int>{};
    for (final entry in note.amounts) {
      final currency = entry.currency ?? note.currency ?? 'PHP';
      currencyCounts[currency] = (currencyCounts[currency] ?? 0) + 1;
    }
    final currency = currencyCounts.entries.fold<String>(
      note.currency ?? 'PHP',
      (current, entry) =>
          entry.value > (currencyCounts[current] ?? 0) ? entry.key : current,
    );
    // Entries excluded from the cards above because their currency differs
    // from the note's dominant currency — surfaced so totals stay honest.
    final excludedSpent = <String, int>{};
    final excludedCounts = <String, int>{};
    for (final entry in note.amounts) {
      final cur = entry.currency ?? note.currency ?? 'PHP';
      if (cur == currency) continue;
      excludedCounts[cur] = (excludedCounts[cur] ?? 0) + 1;
      if ((entry.type ?? note.type) == 'expense') {
        excludedSpent[cur] = (excludedSpent[cur] ?? 0) + entry.amount;
      }
    }
    final expenses = note.amounts
        .where((e) =>
            (e.type ?? note.type) == 'expense' &&
            (e.currency ?? note.currency ?? 'PHP') == currency)
        .toList();
    final incomes = note.amounts
        .where((e) =>
            (e.type ?? note.type) == 'income' &&
            (e.currency ?? note.currency ?? 'PHP') == currency)
        .toList();
    final totalExpenses = expenses.fold<int>(0, (s, e) => s + e.amount);
    final totalIncome = incomes.fold<int>(0, (s, e) => s + e.amount);
    final netAmount = totalIncome - totalExpenses;
    return Flexible(
      child: Container(
        margin: EdgeInsets.fromLTRB(_horizontalPad, 12, _horizontalPad, 0),
        decoration: BoxDecoration(
          color: context.colors.listBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryCards(totalExpenses, totalIncome, netAmount, currency),
            if (excludedCounts.isNotEmpty)
              _buildExcludedCurrenciesRow(excludedSpent, excludedCounts),
            if (note.amounts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Divider(height: 1, color: context.colors.border.withAlpha(100)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: note.amounts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      _buildTransactionItem(note, note.amounts[index]),
                ),
              ),
              const SizedBox(height: 6),
              _buildAddEntryButton(note),
              const SizedBox(height: 12),
            ] else ...[
              Expanded(
                child: Center(
                  child: Text(
                    'No entries yet. Tap "+ Entry" to add one.',
                    style: TextStyle(fontSize: AppType.t12, color: context.colors.muted),
                  ),
                ),
              ),
              _buildAddEntryButton(note),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExcludedCurrenciesRow(
    Map<String, int> excludedSpent,
    Map<String, int> excludedCounts,
  ) {
    final muted = context.colors.muted;
    final style = TextStyle(fontSize: AppType.t11, color: muted);
    final codes = excludedCounts.keys.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < codes.length; i++) {
      final code = codes[i];
      final n = excludedCounts[code] ?? 0;
      if (i > 0) spans.add(TextSpan(text: ' · ', style: style));
      spans.add(currencySpan(code, style));
      spans.add(
        TextSpan(
          text:
              '${formatMinor(excludedSpent[code] ?? 0, code)} spent in $n $code ${n == 1 ? 'entry' : 'entries'}',
          style: style,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 12, color: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(text: 'Excludes ', style: style),
                  ...spans,
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    int totalExpenses,
    int totalIncome,
    int netAmount,
    String currency,
  ) {
    final expenseColor = context.colors.destructive;
    final incomeColor = context.colors.income;
    final netColor = netAmount >= 0 ? incomeColor : expenseColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: _summaryCard(
                  'EXPENSES',
                  totalExpenses,
                  expenseColor,
                  currency,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _summaryCard(
                  'INCOME',
                  totalIncome,
                  incomeColor,
                  currency,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                child: _summaryCard('NET', netAmount, netColor, currency),
              ),
              const Spacer(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String label,
    int value,
    Color color,
    String currency,
  ) {
    return Container(
      height: 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.t11,
              fontWeight: FontWeight.w500,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: AppType.t22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                children: [
                  currencySpan(currency, null),
                  TextSpan(
                    text: formatMinor(value, currency),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Note note, MoneyEntry e) {
    final effectiveCurrency = e.currency ?? note.currency;
    final effectiveType = e.type ?? note.type;
    final effectiveCurrencySym = effectiveCurrency ?? 'PHP';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              _categoryIcon(e.category),
              size: 20,
              color: context.colors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    e.category,
                    style: TextStyle(fontSize: AppType.t13_5, color: context.colors.fg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (e.note != null && e.note!.isNotEmpty)
                    Text(
                      e.note!,
                      style: TextStyle(
                        fontSize: AppType.t11,
                        color: context.colors.muted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: AppType.t13_5,
                      fontWeight: FontWeight.w500,
                      color: effectiveType == 'income'
                          ? context.colors.income
                          : context.colors.fg,
                    ),
                    children: [
                      currencySpan(effectiveCurrencySym, null),
                      TextSpan(
                        text: formatMinor(e.amount, effectiveCurrency),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${e.date.hour.toString().padLeft(2, '0')}:${e.date.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: AppType.t10,
                    fontFamily: context.colors.monoFontFamily,
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
            if (e.isRecurring)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.loop, size: 12, color: context.colors.muted),
              ),
            InkWell(
              onTap: () => EntrySheet.show(
                context,
                entry: e,
                onSave: _addOrUpdateEntry,
                currencySymbol: currencySymbol(effectiveCurrency),
                noteCurrency: note.currency,
                noteType: note.type,
                customCategories: widget.customCategories,
                recentCategories: widget.recentCategories,
                onCategoryUsed: widget.onCategoryUsed,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Tooltip(
                  message: 'Edit entry',
                  child: Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: () => _removeEntry(e.id),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Tooltip(
                  message: 'Delete entry',
                  child: Icon(Icons.close, size: 14, color: context.colors.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddEntryButton(Note note) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => EntrySheet.show(
          context,
          onSave: _addOrUpdateEntry,
          currencySymbol: currencySymbol(note.currency),
          noteCurrency: note.currency,
          noteType: note.type,
          customCategories: widget.customCategories,
          recentCategories: widget.recentCategories,
          onCategoryUsed: widget.onCategoryUsed,
        ),
        icon: const Icon(Icons.add, size: 14),
        label: const Text('Entry', style: TextStyle(fontSize: AppType.t13_5)),
        style: TextButton.styleFrom(
          foregroundColor: context.colors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'food & drink':
      case 'dining':
      case 'restaurant':
        return Icons.restaurant_outlined;
      case 'transport':
      case 'transportation':
      case 'gas':
      case 'fuel':
        return Icons.directions_car_outlined;
      case 'shopping':
      case 'clothing':
        return Icons.shopping_bag_outlined;
      case 'bills':
      case 'utilities':
      case 'electric':
      case 'water':
        return Icons.receipt_outlined;
      case 'entertainment':
      case 'movies':
      case 'games':
        return Icons.movie_outlined;
      case 'health':
      case 'medical':
      case 'fitness':
        return Icons.health_and_safety_outlined;
      case 'education':
      case 'school':
      case 'tuition':
        return Icons.school_outlined;
      case 'salary':
      case 'work':
      case 'income':
        return Icons.work_outlined;
      case 'freelance':
      case 'freelancing':
        return Icons.laptop_outlined;
      case 'investment':
      case 'stocks':
      case 'dividend':
        return Icons.trending_up_outlined;
      case 'groceries':
      case 'supermarket':
        return Icons.local_grocery_store_outlined;
      case 'rent':
      case 'housing':
      case 'mortgage':
        return Icons.home_outlined;
      case 'travel':
      case 'hotel':
      case 'vacation':
        return Icons.flight_outlined;
      case 'coffee':
      case 'cafe':
      case 'drinks':
        return Icons.coffee_outlined;
      case 'insurance':
        return Icons.shield_outlined;
      case 'subscription':
      case 'streaming':
        return Icons.subscriptions_outlined;
      case 'gift':
      case 'donation':
      case 'charity':
        return Icons.card_giftcard_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  // ---- Checklist helpers ----

  List<_ChecklistItem> _parseChecklist(String text) {
    final items = <_ChecklistItem>[];
    final lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final m = RegExp(r'^\s*-\s+\[([ xX])\]\s+(.*)$').firstMatch(lines[i]);
      if (m != null) {
        items.add(
          _ChecklistItem(i, m.group(1)!.toLowerCase() == 'x', m.group(2) ?? ''),
        );
      }
    }
    return items;
  }

  void _toggleItem(int lineIndex, bool checked) {
    final lines = _contentCtrl.text.split('\n');
    lines[lineIndex] = lines[lineIndex].replaceFirst(
      RegExp(r'\[[ xX]\]'),
      checked ? '[x]' : '[ ]',
    );
    _contentCtrl.text = lines.join('\n');
    _syncContent();
    setState(() {});
  }

  void _deleteItem(int lineIndex) {
    final lines = _contentCtrl.text.split('\n');
    lines.removeAt(lineIndex);
    _contentCtrl.text = lines.join('\n');
    _syncContent();
    setState(() {});
  }

  void _addItem(String text) {
    if (text.trim().isEmpty) return;
    _contentCtrl.text = '${_contentCtrl.text}- [ ] ${text.trim()}\n';
    _checklistAddCtrl.clear();
    _syncContent();
    setState(() {});
  }

  void _startEdit(int idx, String text) {
    _checklistEditIdx = idx;
    _checklistEditCtrl.text = text;
    _checklistEditFocus.requestFocus();
    setState(() {});
  }

  void _submitEdit(int lineIndex, int visualIndex, {bool addNext = false}) {
    final text = _checklistEditCtrl.text.trim();
    if (text.isEmpty) {
      if (visualIndex > 0) _deleteItem(lineIndex);
      _checklistEditIdx = null;
      setState(() {});
      return;
    }
    final lines = _contentCtrl.text.split('\n');
    final m = RegExp(r'^(\s*-\s+\[[ xX]\]\s+).*$').firstMatch(lines[lineIndex]);
    if (m != null) lines[lineIndex] = '${m.group(1)}$text';
    if (!addNext) {
      _contentCtrl.text = lines.join('\n');
      _syncContent();
      _checklistEditIdx = null;
      setState(() {});
      return;
    }
    lines.insert(lineIndex + 1, '- [ ] ');
    _contentCtrl.text = lines.join('\n');
    _syncContent();
    _checklistEditIdx = visualIndex + 1;
    _checklistEditCtrl.text = '';
    _checklistEditFocus.requestFocus();
    setState(() {});
  }

  Widget _buildChecklistPanel() {
    final horizontalPad = _horizontalPad;
    final c = context.colors;
    final items = _parseChecklist(_contentCtrl.text);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        padding: EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checklist_outlined,
                              size: 40,
                              color: c.muted.withAlpha(80),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No items yet',
                              style: _editorFont(
                                display: true,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: c.fg,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add your first to-do item below.',
                              style: TextStyle(fontSize: AppType.t13_5, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => _buildChecklistRow(items[i], i),
                    ),
            ),
            _buildAddRow(c),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showRawDialog,
                icon: Icon(Icons.edit_outlined, size: 14, color: c.muted),
                label: Text(
                  'Edit raw',
                  style: TextStyle(fontSize: AppType.t12, color: c.muted),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistRow(_ChecklistItem item, int index) {
    final c = context.colors;
    final editing = _checklistEditIdx == index;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: item.checked,
            onChanged: (_) => _toggleItem(item.lineIndex, !item.checked),
            activeColor: c.accent,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: editing
                ? SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _checklistEditCtrl,
                      focusNode: _checklistEditFocus,
                      style: _editorFont(
                        fontSize: AppType.t13_5,
                        fontWeight: FontWeight.w400,
                        color: c.fg,
                        height: 1.4,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 4,
                        ),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) =>
                          _submitEdit(item.lineIndex, index, addNext: true),
                      onTapOutside: (_) => _submitEdit(item.lineIndex, index),
                    ),
                  )
                : GestureDetector(
                    onTap: () => _startEdit(index, item.text),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        stripInlineMarkdown(item.text),
                        style: _editorFont(
                          fontSize: AppType.t13_5,
                          fontWeight: item.checked
                              ? FontWeight.w400
                              : FontWeight.w500,
                          color: item.checked ? c.muted : c.fg,
                          height: 1.4,
                        ).copyWith(
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
          if (!editing)
            GestureDetector(
              onTap: () => _deleteItem(item.lineIndex),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: c.muted.withAlpha(120),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddRow(AppColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 18,
            color: c.accent.withAlpha(180),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _checklistAddCtrl,
                style: _editorFont(
                  fontSize: AppType.t13_5,
                  fontWeight: FontWeight.w400,
                  color: c.fg,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'Add an item...',
                  hintStyle: TextStyle(
                    fontSize: AppType.t13_5,
                    color: c.muted.withAlpha(150),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 6,
                  ),
                  border: InputBorder.none,
                ),
                onSubmitted: (v) {
                  _addItem(v);
                  _checklistAddCtrl.clear();
                },
              ),
            ),
          ),
          TextButton(
            onPressed: () => _addItem(_checklistAddCtrl.text),
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(44, 44),
            ),
            child: const Text(
              'Add',
              style: TextStyle(fontSize: AppType.t13_5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRawDialog() async {
    final c = context.colors;
    final ctrl = TextEditingController(text: _contentCtrl.text);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.panel)),
        title: Text(
          'Raw markdown',
          style: TextStyle(
            fontSize: AppType.t13_5,
            fontWeight: FontWeight.w600,
            color: c.fg,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(context).height * 0.4,
          child: TextField(
            controller: ctrl,
            maxLines: null,
            expands: true,
            style: GoogleFonts.jetBrainsMono(
              fontSize: AppType.t12,
              color: c.fg,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                borderSide: BorderSide(color: c.border),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: c.muted)),
          ),
          TextButton(
            onPressed: () {
              _contentCtrl.text = ctrl.text;
              _syncContent();
              setState(() {});
              Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: c.accent)),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Widget _buildTagBar() {
    final tags = widget.note?.tags ?? [];
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(_horizontalPad, 0, _horizontalPad, 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...tags.map(
            (t) => InkWell(
              onTap: () => _removeTag(t),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.tagBg,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$t',
                      style: TextStyle(
                        fontSize: AppType.t12,
                        fontWeight: FontWeight.w400,
                        color: c.tagFg,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close, size: 12, color: c.tagFg),
                  ],
                ),
              ),
            ),
          ),
          if (_addingTag)
            IntrinsicWidth(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80),
                child: TextField(
                  controller: _newTagCtrl,
                  focusNode: _newTagFocus,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    hintText: 'tag',
                    hintStyle: TextStyle(fontSize: AppType.t12, color: c.muted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: BorderSide(color: c.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      borderSide: BorderSide(color: c.accent),
                    ),
                  ),
                  style: TextStyle(fontSize: AppType.t12, color: c.fg),
                  onSubmitted: _submitTag,
                  onEditingComplete: () => _submitTag(_newTagCtrl.text),
                  onTapOutside: (_) {
                    if (_newTagCtrl.text.trim().isEmpty) {
                      setState(() => _addingTag = false);
                    }
                  },
                ),
              ),
            )
          else
            InkWell(
              onTap: () {
                setState(() => _addingTag = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _newTagFocus.requestFocus();
                });
              },
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 12, color: c.muted),
                    const SizedBox(width: 4),
                    Text('tag', style: TextStyle(fontSize: AppType.t12, color: c.muted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _submitTag(String value) {
    final tag = value.trim().replaceAll(RegExp(r'\s+'), '-');
    if (tag.isEmpty) {
      setState(() {
        _addingTag = false;
        _newTagCtrl.clear();
      });
      return;
    }
    final current = List<String>.from(widget.note?.tags ?? const []);
    if (current.contains(tag)) {
      setState(() {
        _addingTag = false;
        _newTagCtrl.clear();
      });
      return;
    }
    current.add(tag);
    widget.onTagsChange(current);
    setState(() {
      _newTagCtrl.clear();
    });
  }

  void _removeTag(String tag) {
    final current = List<String>.from(widget.note?.tags ?? const []);
    current.remove(tag);
    widget.onTagsChange(current);
  }

  Widget _buildBody() {
    final horizontalPad = _horizontalPad;
    if (widget.previewMode) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640),
          padding: EdgeInsets.fromLTRB(horizontalPad, 16, horizontalPad, 0),
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: _renderedContent(),
              selectable: true,
              styleSheet: _buildMarkdownStyle(context.colors, _editorFont),
              onTapLink: (text, href, title) {
                if (href != null && href.startsWith('#note:')) {
                  widget.onOpenNote(href.substring(6));
                }
              },
              builders: {
                'pre': _CodeBlockBuilder(
                  context.colors.sidebarFg,
                  context.colors.monoFontFamily,
                ),
              },
              sizedImageBuilder: (config) {
                final path = kIsWeb
                    ? config.uri.toString()
                    : resolveImagePath(
                        config.uri,
                        windows: !kIsWeb && Platform.isWindows,
                      );
                if (kIsWeb && path.startsWith('data:image/')) {
                  final comma = path.indexOf(',');
                  if (comma > 0) {
                    try {
                      final bytes = base64Decode(path.substring(comma + 1));
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: Image.memory(
                            Uint8List.fromList(bytes),
                            fit: BoxFit.contain,
                            width: config.width ?? double.infinity,
                            errorBuilder: (_, __, ___) =>
                                _brokenImage(config.alt),
                          ),
                        ),
                      );
                    } catch (_) {
                      return _brokenImage(config.alt);
                    }
                  }
                }
                if (!kIsWeb && File(path).existsSync()) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        width: config.width ?? double.infinity,
                        cacheWidth: 1600,
                        errorBuilder: (_, __, ___) => _brokenImage(config.alt),
                      ),
                    ),
                  );
                }
                return _brokenImage(config.alt);
              },
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxBodyWidth = 640.0;
        final available = constraints.maxWidth - horizontalPad * 2;
        final bodyWidth = available > maxBodyWidth ? maxBodyWidth : available;
        final leftPad = (constraints.maxWidth - bodyWidth) / 2;
        final bodyStyle = _editorFont(
          fontSize: AppType.t15,
          fontWeight: FontWeight.w400,
          color: context.colors.fg,
          height: 1.6,
        );
        return Stack(
          children: [
            SizedBox.expand(),
            Positioned(
              left: leftPad,
              right: leftPad,
              top: 16,
              bottom: 16,
              child: IgnorePointer(
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(0, -_bodyScrollOffset),
                    child: RichText(
                      key: const Key('md-highlight-layer'),
                      text: TextSpan(
                        style: bodyStyle,
                        children: highlightMarkdownSpans(
                          _contentCtrl.text,
                          base: bodyStyle,
                          syntax: context.colors.muted.withAlpha(150),
                          link: context.colors.accent,
                          codeBg: context.colors.muted.withAlpha(26),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: leftPad,
              right: leftPad,
              top: 16,
              bottom: 16,
                child: Focus(
                  onKeyEvent: _handleEditorKey,
                  child: TextField(
                    focusNode: _contentFocus,
                    controller: _contentCtrl,
                    scrollController: _bodyScroll,
                    onChanged: (_) => _syncContent(),
                    maxLines: null,
                    expands: true,
                    cursorColor: context.colors.fg,
                    style: bodyStyle.copyWith(color: Colors.transparent),
                  decoration: InputDecoration(
                    hintText:
                        'Start writing in Markdown...\n\n'
                        'Type / for blocks, #tag to categorize, and '
                        '[[ to link another note.',
                    hintStyle: TextStyle(color: context.colors.muted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            if (_slashSuggestions.isNotEmpty)
              Positioned(
                left: leftPad,
                right: leftPad,
                top: 16,
                child: _buildSlashSuggestions(),
              ),
            if (_slashSuggestions.isEmpty && _linkSuggestions.isNotEmpty)
              Positioned(
                left: leftPad,
                right: leftPad,
                top: 16,
                child: _buildLinkSuggestions(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSlashSuggestions() {
    final c = context.colors;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _slashSuggestions.asMap().entries.map((entry) {
            final index = entry.key;
            final command = entry.value;
            final selected = index == _slashSelectedIndex;
            return InkWell(
              onTap: () => _insertSlashCommand(command),
              child: Container(
                color: selected ? c.accentDim : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8, horizontal: 12),
                child: Row(
                  children: [
                    Icon(command.icon, size: 16, color: selected ? c.accent : c.muted),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        command.label,
                        style: TextStyle(
                          color: c.fg,
                          fontSize: AppType.t13_5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      command.description,
                      style: TextStyle(color: c.muted, fontSize: AppType.t11),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLinkSuggestions() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _linkSuggestions
              .map(
                (n) => InkWell(
                  onTap: () => _insertLink(n),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 14,
                          color: context.colors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            n.title,
                            style: TextStyle(
                              fontSize: AppType.t13_5,
                              color: context.colors.fg,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _brokenImage(String? alt) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.listBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: context.colors.muted,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alt ?? 'Image not found',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: AppType.t13_5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 36,
            color: context.colors.muted.withAlpha(64),
          ),
          const SizedBox(height: 12),
          Text(
            'Nothing here yet',
            style: _editorFont(
              display: true,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: context.colors.muted.withAlpha(100),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ctrl+N \u2014 new note',
            style: TextStyle(
              fontSize: AppType.t11,
              fontFamily: context.colors.monoFontFamily,
              color: context.colors.muted.withAlpha(80),
              letterSpacing: 0.06,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem {
  final int lineIndex;
  final bool checked;
  final String text;
  const _ChecklistItem(this.lineIndex, this.checked, this.text);
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final Color codeColor;
  final String fontFamily;
  _CodeBlockBuilder(this.codeColor, this.fontFamily);

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return Text(
      text.textContent,
      style: TextStyle(
        fontSize: AppType.t13_5,
        fontFamily: fontFamily,
        color: codeColor,
        height: 1.55,
      ),
    );
  }
}

/// Instance method so the markdown preview picks up the Settings font choice
/// (display font for headings, UI font for body) instead of hardcoded DM Sans.
MarkdownStyleSheet _buildMarkdownStyle(
  AppColors c,
  TextStyle Function({
    bool display,
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  })
  editorFont,
) {
  return MarkdownStyleSheet(
    h1: editorFont(
      display: true,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: c.fg,
      letterSpacing: -0.02,
      height: 1.3,
    ),
    h2: editorFont(
      display: true,
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: c.fg,
      letterSpacing: -0.01,
      height: 1.3,
    ),
    h3: editorFont(
      display: true,
      fontSize: AppType.t15,
      fontWeight: FontWeight.w600,
      color: c.fg,
      height: 1.3,
    ),
    p: editorFont(
      fontSize: AppType.t15,
      fontWeight: FontWeight.w400,
      color: c.fg,
      height: 1.6,
    ),
    code: TextStyle(
      fontSize: AppType.t13_5,
      fontFamily: c.monoFontFamily,
      backgroundColor: c.listBg,
      color: c.fg,
    ),
    codeblockDecoration: BoxDecoration(
      color: c.sidebarBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: c.border),
    ),
    codeblockPadding: const EdgeInsets.all(14),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
    a: TextStyle(color: c.accent),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    listBullet: editorFont(fontSize: AppType.t15, color: c.fg),
    checkbox: editorFont(fontSize: AppType.t15, color: c.accent),
    del: TextStyle(decoration: TextDecoration.lineThrough, color: c.muted),
    em: const TextStyle(fontStyle: FontStyle.italic),
  );
}

class _TypeDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _TypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isFinance = value == 'expense' || value == 'income';
    final isTodo = value == 'todo';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isFinance
            ? context.colors.accentDim
            : isTodo
            ? context.colors.accentDim
            : context.colors.listBg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(
          color: isFinance
              ? context.colors.accent
              : isTodo
              ? context.colors.accent
              : context.colors.border,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Note type',
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'text', child: Text('Text')),
          PopupMenuItem(value: 'todo', child: Text('Todo')),
          PopupMenuItem(value: 'expense', child: Text('Expense')),
          PopupMenuItem(value: 'income', child: Text('Income')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label(value),
              style: TextStyle(
                fontSize: AppType.t12,
                fontWeight: FontWeight.w500,
                color: isFinance || isTodo
                    ? context.colors.accent
                    : context.colors.muted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: isFinance || isTodo
                  ? context.colors.accent
                  : context.colors.muted,
            ),
          ],
        ),
      ),
    );
  }

  String _label(String v) {
    switch (v) {
      case 'todo':
        return 'Todo';
      case 'expense':
        return 'Expense';
      case 'income':
        return 'Income';
      default:
        return 'Text';
    }
  }
}

class _CurrencyDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CurrencyDropdown({required this.value, required this.onChanged});

  static const currencies = ['PHP', 'USD', 'EUR', 'GBP', 'JPY', 'INR'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.listBg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: context.colors.border),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Currency',
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => currencies
            .map(
              (code) => PopupMenuItem(
                value: code,
                child: Text.rich(
                  TextSpan(
                    children: [
                      currencySpan(code, null),
                      const TextSpan(text: ' '),
                      TextSpan(text: code),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: AppType.t12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.fg,
                ),
                children: [
                  currencySpan(value, null),
                  const TextSpan(text: ' '),
                  TextSpan(text: value),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
