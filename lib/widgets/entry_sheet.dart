import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../models/money_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../utils/date_format.dart';
import '../utils/finance_utils.dart';
import '../utils/id.dart';

const List<String> kDefaultCategories = [
  'Food',
  'Transport',
  'Groceries',
  'Bills',
  'Health',
  'Shopping',
  'Entertainment',
  'Other',
  'Pamasahe',
  'Load',
  'Padala',
  'Merkado',
  'Kuryente',
  'Tubig',
];

const List<String> kDefaultPaymentMethods = [
  'Cash',
  'GCash',
  'Maya',
  'Credit Card',
  'Bank Transfer',
];

const List<String> kCurrencies = ['PHP', 'USD', 'EUR', 'GBP', 'JPY', 'INR'];

class EntrySheet extends StatefulWidget {
  final MoneyEntry? entry;
  final void Function(MoneyEntry) onSave;
  final String currencySymbol;
  final String? noteCurrency;
  final String? noteType;
  final List<String> customCategories;
  final List<String> recentCategories;
  final void Function(String category)? onCategoryUsed;

  const EntrySheet({
    super.key,
    this.entry,
    required this.onSave,
    this.currencySymbol = '',
    this.noteCurrency,
    this.noteType,
    this.customCategories = const [],
    this.recentCategories = const [],
    this.onCategoryUsed,
  });

  static Future<void> show(
    BuildContext context, {
    MoneyEntry? entry,
    required void Function(MoneyEntry) onSave,
    String currencySymbol = '',
    String? noteCurrency,
    String? noteType,
    List<String> customCategories = const [],
    List<String> recentCategories = const [],
    void Function(String category)? onCategoryUsed,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: EntrySheet(
          entry: entry,
          onSave: onSave,
          currencySymbol: currencySymbol,
          noteCurrency: noteCurrency,
          noteType: noteType,
          customCategories: customCategories,
          recentCategories: recentCategories,
          onCategoryUsed: onCategoryUsed,
        ),
      ),
    );
  }

  @override
  State<EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<EntrySheet> {
  late TextEditingController _amountCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _noteCtrl;
  late DateTime _date;
  late FocusNode _amountFocusNode;
  String? _paymentMethod;
  String? _entryCurrency;
  bool _showCurrencyPicker = false;
  bool _isRecurring = false;
  String? _recurInterval;
  DateTime? _recurEnd;
  String? _entryType;
  bool _showMore = false;
  bool _showAllCategories = false;
  bool _isScanning = false;
  String? _amountError;
  String? _recurError;
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer? _textRecognizer =
      kIsWeb ? null : TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _amountFocusNode = FocusNode();
    _amountCtrl = TextEditingController(
        text: e != null
            ? minorToMajor(
                e.amount,
                e.currency ?? widget.noteCurrency,
              ).toStringAsFixed(
                currencyDecimals(e.currency ?? widget.noteCurrency),
              )
            : '');
    _categoryCtrl = TextEditingController(text: e?.category ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _date = e?.date ?? DateTime.now();
    _paymentMethod = e?.paymentMethod;
    _entryCurrency = e?.currency;
    _isRecurring = e?.isRecurring ?? false;
    _recurInterval = e?.recurInterval;
    _recurEnd = e?.recurEnd;
    _entryType = e?.type ?? widget.noteType ?? 'expense';
    if (e == null && _amountCtrl.text.isEmpty) {
      _amountCtrl.selection = TextSelection.collapsed(offset: 0);
    }
  }

  @override
  void dispose() {
    try { _textRecognizer?.close(); } catch (_) {}
    _amountFocusNode.dispose();
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  MoneyEntry? _doSave() {
    final amount =
        parseAmountToMinor(_amountCtrl.text, _entryCurrency ?? widget.noteCurrency);
    if (amount == null) {
      setState(() => _amountError = _amountCtrl.text.trim().isEmpty
          ? 'Enter an amount to save this entry.'
          : 'Use numbers only, with up to 2 decimals (e.g. 250 or 250.50).');
      return null;
    }
    if (amount <= 0) {
      setState(() => _amountError = 'Amount must be greater than 0.');
      return null;
    }
    if (_isRecurring && _recurInterval == null) {
      setState(() =>
          _recurError = 'Choose a repeat interval, or turn off repeat.');
      return null;
    }
    if (_amountError != null || _recurError != null) {
      setState(() {
        _amountError = null;
        _recurError = null;
      });
    }
    final category = _categoryCtrl.text.trim().isEmpty
        ? 'Uncategorized'
        : _categoryCtrl.text.trim();
    final noteText = _noteCtrl.text.trim();
    final entry = MoneyEntry(
      id: widget.entry?.id ?? generateId('m'),
      amount: amount,
      category: category,
      date: _date,
      note: noteText.isEmpty ? null : noteText,
      paymentMethod: _paymentMethod,
      currency: _entryCurrency,
      type: _entryType,
      isRecurring: _isRecurring,
      recurInterval: _isRecurring ? _recurInterval : null,
      recurEnd: _isRecurring ? _recurEnd : null,
      // Keep the generation anchor even when recurrence is toggled off;
      // dropping it re-anchors to the master date on re-enable and
      // duplicates the whole series.
      lastGenerated: _isRecurring
          ? (widget.entry?.lastGenerated ?? _date)
          : widget.entry?.lastGenerated,
    );
    widget.onSave(entry);
    widget.onCategoryUsed?.call(category);
    return entry;
  }

  void _save() {
    if (_doSave() != null) Navigator.pop(context);
  }

  Future<void> _saveAndNext() async {
    if (_isRecurring && _recurInterval != null) {
      // Rapid-fire saving would otherwise create N masters, each generating
      // its own full series on the next launch.
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('This entry is recurring'),
          content: const Text(
            '“Add & Next” keeps the recurrence settings. Each save creates '
            'a separate recurring series from this date.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'once'),
              child: const Text('Save once'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'recurring'),
              child: const Text('Keep recurring'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'once') _isRecurring = false;
    }
    if (_doSave() == null) return;
    setState(() {
      _amountCtrl.text = '';
    });
    _amountFocusNode.requestFocus();
  }

  // ponytail: scan receipt via camera, run OCR, parse out the largest
  // currency-shaped number, pre-fill amount + note. Best-effort —
  // the user reviews everything before saving.
  // Disabled on web: google_mlkit_text_recognition has no web implementation.
  Future<void> _scanReceipt() async {
    if (_isScanning || kIsWeb || _textRecognizer == null) return;
    setState(() => _isScanning = true);
    try {
      final picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      final inputImage = InputImage.fromFilePath(picked.path);
      final result = await _textRecognizer.processImage(inputImage);
      final text = result.text.trim();
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No text detected in image'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      // ponytail: match currency-shaped numbers like 1,234.56 or 1234.56,
      // optionally preceded by ₱, PHP, Total, etc. Pick the largest.
      final matches = RegExp(
        r'(?:[\u20B1]|PHP\s*|Total[:\s]*)?(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{2})|\d+(?:\.\d{2}))',
        caseSensitive: false,
      ).allMatches(text);
      double largest = 0;
      String? bestRaw;
      for (final m in matches) {
        final raw = (m.group(1) ?? '').replaceAll(',', '').replaceAll(' ', '');
        final v = double.tryParse(raw);
        if (v != null && v > largest) {
          largest = v;
          bestRaw = raw;
        }
      }
      if (!mounted) return;
      final approved = await _reviewScan(
        text: text,
        amount: largest,
        rawAmount: bestRaw,
      );
      if (approved != true || !mounted) return;
      if (largest > 0) {
        _amountCtrl.text = bestRaw!;
      }
      // Append the raw text to the note field if it's empty
      if (_noteCtrl.text.trim().isEmpty) {
        _noteCtrl.text = text.length > 200
            ? '${text.substring(0, 200)}...'
            : text;
      }
      setState(() {
        _amountError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(largest > 0
              ? 'Scanned — found ${widget.currencySymbol}${largest.toStringAsFixed(2)}'
              : 'Scanned — no amount detected, text added to note'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<bool?> _reviewScan({
    required String text,
    required double amount,
    required String? rawAmount,
  }) {
    final preview = text.length > 240 ? '${text.substring(0, 240)}...' : text;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Review scanned receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amount > 0
                  ? 'Detected amount: ${widget.currencySymbol}${amount.toStringAsFixed(2)}'
                  : 'No amount was detected.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (rawAmount != null) ...[
              const SizedBox(height: 4),
              const Text(
                'Review the amount field after applying. OCR can mistake totals, dates, or tax values.',
                style: TextStyle(fontSize: AppType.t12),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              preview,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppType.t12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply scan'),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _inlineError(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        msg,
        style: TextStyle(fontSize: AppType.t12, color: context.colors.destructive),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.entry != null;

    final allCats = <String>{
      ...kDefaultCategories,
      ...widget.customCategories,
      if (_categoryCtrl.text.trim().isNotEmpty) _categoryCtrl.text.trim(),
    }.toList();
    allCats.sort((a, b) {
      final aDef = kDefaultCategories.contains(a) ? 0 : 1;
      final bDef = kDefaultCategories.contains(b) ? 0 : 1;
      if (aDef != bDef) return aDef.compareTo(bDef);
      return a.compareTo(b);
    });

    final recent = widget.recentCategories.isNotEmpty
        ? widget.recentCategories
            .where((c) => allCats.contains(c))
            .take(6)
            .toList()
        : kDefaultCategories.take(6).toList();
    final displayCats =
        _showAllCategories ? allCats : recent;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -- Drag handle --
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // -- Title --
            Text(isEdit ? 'Edit entry' : 'Add entry',
                style:  TextStyle(
                  fontSize: AppType.t15, fontWeight: FontWeight.w600,
                  color: context.colors.fg, letterSpacing: 0.01,
                )),
            const SizedBox(height: 16),

            // -- Expense / Income Toggle --
            if (_entryType != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _TypeToggleChip(
                    label: 'Expense',
                    active: _entryType == 'expense',
                    activeColor: context.colors.destructive,
                    onTap: () =>
                        setState(() => _entryType = 'expense'),
                  ),
                  const SizedBox(width: 8),
                  _TypeToggleChip(
                    label: 'Income',
                    active: _entryType == 'income',
                    activeColor: context.colors.income,
                    onTap: () =>
                        setState(() => _entryType = 'income'),
                  ),
                ],
              ),
            const SizedBox(height: 16),

            // -- Amount field --
            _Field(
              label:
                  'Amount · ${_entryCurrency ?? widget.noteCurrency ?? 'PHP'}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _amountCtrl,
                    focusNode: _amountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: kAmountInputFormatters,
                    autofocus: !isEdit,
                    decoration: _inputDeco(
                      widget.currencySymbol.isNotEmpty
                          ? '${widget.currencySymbol}0.00'
                          : '0.00',
                      error: _amountError != null,
                    ),
                    onChanged: (_) {
                      if (_amountError != null) {
                        setState(() => _amountError = null);
                      }
                    },
                    style:  TextStyle(
                      fontSize: AppType.t15, fontWeight: FontWeight.w500,
                      color: context.colors.fg,
                    ),
                  ),
                  if (_amountError != null) _inlineError(_amountError!),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // -- Category section --
            _Field(
              label: 'Category · optional',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: displayCats.map((cat) {
                      final selected = _categoryCtrl.text.trim() == cat;
                      return InkWell(
                        onTap: () {
                          setState(() => _categoryCtrl.text = cat);
                        },
                        borderRadius: BorderRadius.circular(AppRadius.panel),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.accentDim
                                : context.colors.listBg,
                            borderRadius: BorderRadius.circular(AppRadius.panel),
                            border: Border.all(
                              color: selected
                                  ? context.colors.accent
                                  : context.colors.border,
                            ),
                          ),
                          child: Text(cat,
                              style: TextStyle(
                                fontSize: AppType.t12,
                                color: selected
                                    ? context.colors.accent
                                    : context.colors.fg,
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                  if (!_showAllCategories && allCats.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _showAllCategories = true),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Text(
                            'More Categories',
                            style: TextStyle(
                              fontSize: AppType.t12,
                              fontWeight: FontWeight.w500,
                              color: context.colors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _categoryCtrl,
                    decoration: _inputDeco('Or type your own'),
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: AppType.t13_5, color: context.colors.fg),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // -- More options toggle --
            InkWell(
              onTap: () => setState(() => _showMore = !_showMore),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showMore ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: context.colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                     _showMore ? 'Hide details' : 'Show details',
                      style: TextStyle(
                        fontSize: AppType.t12, color: context.colors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -- Collapsible more options --
            if (_showMore) ...[
              const SizedBox(height: 12),

              // Currency
              _Field(
                label: 'Currency',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => setState(
                          () => _showCurrencyPicker = !_showCurrencyPicker),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          color: context.colors.listBg,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: Row(children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                  fontSize: AppType.t13_5, color: context.colors.fg),
                              children: [
                                currencySpan(
                                  _entryCurrency ?? widget.noteCurrency,
                                  null,
                                ),
                                TextSpan(
                                  text: _entryCurrency != null
                                      ? ' $_entryCurrency'
                                      : ' (note default)',
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.arrow_drop_down,
                              size: 16, color: context.colors.muted),
                        ]),
                      ),
                    ),
                    if (_showCurrencyPicker)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kCurrencies.map((code) {
                            final selected = _entryCurrency == code;
                            return InkWell(
                              onTap: () => setState(() {
                                _entryCurrency = selected ? null : code;
                                _showCurrencyPicker = false;
                              }),
                              borderRadius: BorderRadius.circular(AppRadius.panel),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? context.colors.accentDim
                                      : context.colors.listBg,
                                  borderRadius: BorderRadius.circular(AppRadius.panel),
                                  border: Border.all(
                                    color: selected
                                        ? context.colors.accent
                                        : context.colors.border,
                                  ),
                                ),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: AppType.t12,
                                      color: selected
                                          ? context.colors.accent
                                          : context.colors.fg,
                                    ),
                                    children: [
                                      currencySpan(code, null),
                                      const TextSpan(text: ' '),
                                      TextSpan(text: code),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Date
              _Field(
                label: 'Date',
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: context.colors.listBg,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 14, color: context.colors.muted),
                        const SizedBox(width: 8),
                        Text(_formatDate(_date),
                            style:  TextStyle(
                              fontSize: AppType.t13_5, color: context.colors.fg,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              _Field(
                label: 'Notes',
                child: TextField(
                  controller: _noteCtrl,
                  decoration: _inputDeco(''),
                  style:  TextStyle(fontSize: AppType.t13_5, color: context.colors.fg),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 12),

              // Payment method
              _Field(
                label: 'Payment method',
                child: Wrap(
                  spacing: 6, runSpacing: 6,
                  children: kDefaultPaymentMethods.map((pm) {
                    final selected = _paymentMethod == pm;
                    return InkWell(
                      onTap: () => setState(
                          () => _paymentMethod = selected ? null : pm),
                      borderRadius: BorderRadius.circular(AppRadius.panel),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? context.colors.accentDim
                              : context.colors.listBg,
                          borderRadius: BorderRadius.circular(AppRadius.panel),
                          border: Border.all(
                            color: selected
                                ? context.colors.accent
                                : context.colors.border,
                          ),
                        ),
                        child: Text(pm,
                            style: TextStyle(
                              fontSize: AppType.t12,
                              color: selected
                                  ? context.colors.accent
                                  : context.colors.fg,
                            )),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Scan Receipt
              if (!kIsWeb)
                _Field(
                  label: 'Receipt',
                  child: InkWell(
                    onTap: _isScanning ? null : _scanReceipt,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.listBg,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Row(children: [
                        _isScanning
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.document_scanner_outlined,
                                size: 18, color: context.colors.muted),
                        const SizedBox(width: 8),
                        Text(
                          _isScanning ? 'Scanning...' : 'Scan Receipt',
                          style: TextStyle(
                            fontSize: AppType.t13_5, color: context.colors.fg,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              if (!kIsWeb) const SizedBox(height: 12),

              // Recurring
              _Field(
                label: 'Recurring',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Repeat this entry',
                            style: TextStyle(
                                fontSize: AppType.t13_5, color: context.colors.fg)),
                        const Spacer(),
                        Switch(
                          value: _isRecurring,
                          onChanged: (v) =>
                              setState(() => _isRecurring = v),
                          activeThumbColor: context.colors.accent,
                        ),
                      ],
                    ),
                    if (_isRecurring) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: const ['daily', 'weekly', 'monthly', 'yearly']
                            .map((iv) {
                          final selected = _recurInterval == iv;
                          return InkWell(
                            onTap: () => setState(() {
                              _recurInterval = selected ? null : iv;
                              _recurError = null;
                            }),
                            borderRadius: BorderRadius.circular(AppRadius.panel),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: selected
                                    ? context.colors.accentDim
                                    : context.colors.listBg,
                                borderRadius: BorderRadius.circular(AppRadius.panel),
                                border: Border.all(
                                  color: selected
                                      ? context.colors.accent
                                      : context.colors.border,
                                ),
                              ),
                              child: Text(_capitalize(iv),
                                  style: TextStyle(
                                    fontSize: AppType.t12,
                                    color: selected
                                        ? context.colors.accent
                                        : context.colors.fg,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_recurError != null) _inlineError(_recurError!),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _recurEnd ??
                                DateTime.now()
                                    .add(const Duration(days: 365)),
                            firstDate: _date,
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _recurEnd = picked);
                          }
                        },
                        child: Row(children: [
                          Icon(Icons.event_outlined,
                              size: 14, color: context.colors.muted),
                          const SizedBox(width: 6),
                          Text(
                            _recurEnd != null
                                ? 'Ends ${_formatDate(_recurEnd!)}'
                                : 'No end date',
                            style: TextStyle(
                                fontSize: AppType.t13_5, color: context.colors.fg),
                          ),
                          if (_recurEnd != null) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _recurEnd = null),
                              child: Icon(Icons.close,
                                  size: 14, color: context.colors.muted),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // -- Submit buttons --
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(color: context.colors.fg, fontSize: AppType.t13_5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: isEdit ? null : _saveAndNext,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: Text(isEdit ? '' : 'Add & Next',
                        style: const TextStyle(fontSize: AppType.t12)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.colors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: context.colors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(isEdit ? 'Update' : 'Add Entry',
                        style: TextStyle(
                            color: context.colors.onAccent, fontSize: AppType.t13_5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint, {bool error = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle:  TextStyle(color: context.colors.muted, fontSize: AppType.t13_5),
      filled: true,
      fillColor: context.colors.listBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide:  BorderSide(color: context.colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(
          color: error ? context.colors.destructive : context.colors.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        borderSide: BorderSide(
          color: error ? context.colors.destructive : context.colors.accent,
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => mediumDate(d);
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:  TextStyle(
              fontSize: AppType.t12, fontWeight: FontWeight.w500,
              color: context.colors.muted, letterSpacing: 0.04,
            )),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _TypeToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  const _TypeToggleChip({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withAlpha(30)
              : context.colors.listBg,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(
            color: active ? activeColor : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppType.t12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? activeColor : context.colors.muted,
          ),
        ),
      ),
    );
  }
}
