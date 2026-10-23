/// Money said out loud: "spent 250 on lunch", "grab 180", "paid 1,200 for
/// the electric bill", "got paid 15000". Plain rules, no model: amounts are
/// the one thing speech recognisers reliably write as digits.
class VoiceSpend {
  /// The amount as spoken, in major units ("250", "1200.50"); the app turns
  /// it into minor units in the destination's currency.
  final String amount;

  /// Short description: "Lunch at Jollibee".
  final String note;

  /// One of the finance categories (see kDefaultCategories).
  final String category;

  /// "expense" or "income".
  final String type;

  const VoiceSpend({
    required this.amount,
    required this.note,
    required this.category,
    this.type = 'expense',
  });

  VoiceSpend copyWith({String? amount, String? note, String? category}) =>
      VoiceSpend(
        amount: amount ?? this.amount,
        note: note ?? this.note,
        category: category ?? this.category,
        type: type,
      );
}

// ── amounts ───────────────────────────────────────────────────────────────

final _amount = RegExp(
  r"(?<![\w.])(?:(?<pre>₱|php|p|\$|usd|us\$)\s?)?"
  r"(?<num>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"
  r"(?<k>k\b)?"
  r"(?:\s?(?<post>pesos?|php|bucks|dollars?|usd))?(?![\w])",
  caseSensitive: false,
);

/// Words that make a number a time, a date or a count, not money.
final _notMoneyAfter = RegExp(
  r"^\s*(?:am|pm|a\.m|p\.m|o'?clock|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|years?|times|percent|%|st\b|nd\b|rd\b|th\b|kilos?|kg|km|people|items?|pieces?|pcs)",
  caseSensitive: false,
);
final _notMoneyBefore = RegExp(
  r"(?:\bat|\bby|\bbefore|\bafter|\buntil|\bon\s+the|\bthe|\bin|\bchapter|\bpage|\broom|\bnumber|\bno\.?)\s*$",
  caseSensitive: false,
);

final _spendVerb = RegExp(
  r"\b(?:spent|spend|spending|paid|pay|bought|buy|cost|costs|was|for|on|worth|price|bayad|gastos)\b",
  caseSensitive: false,
);
final _quantity = RegExp(
  r"\b(?:buy|bought|get|grab|pick up|need|order|ordered)\s*$",
  caseSensitive: false,
);
final _thingAfter = RegExp(
  r"^\s+(?!(?:on|for|at|in|from|with|and|today|yesterday|pesos?|php|bucks|dollars?|usd)\b)[a-z]",
  caseSensitive: false,
);
final _incomeVerb = RegExp(
  r"\b(?:got paid|received|receive|earned|earn|salary|income|sold|refund(?:ed)?|sweldo|cashback)\b",
  caseSensitive: false,
);

/// Spends in [clause], or empty. A number counts as money only with a
/// currency, a spending word, or as the whole short clause ("grab 180").
List<VoiceSpend> parseSpends(String input) {
  // "two hundred fifty pesos" → "250 pesos": recognisers don't always
  // write numbers as digits. Only used for money, never the memo text.
  final clause = wordsToDigits(input);
  final out = <VoiceSpend>[];
  final words = clause.trim().split(RegExp(r'\s+'));
  for (final m in _amount.allMatches(clause)) {
    final before = clause.substring(0, m.start);
    final after = clause.substring(m.end);
    if (_notMoneyAfter.hasMatch(after) || _notMoneyBefore.hasMatch(before)) {
      continue;
    }
    final hasCurrency =
        m.namedGroup('pre') != null || m.namedGroup('post') != null;
    final hasVerb = _spendVerb.hasMatch(clause) || _incomeVerb.hasMatch(clause);
    final short = words.length <= 5;
    if (!hasCurrency && !hasVerb && !short) continue;
    var number = m.namedGroup('num')!.replaceAll(',', '');
    final value = double.tryParse(number);
    if (value == null || value <= 0) continue;
    // A bare single digit with no currency is almost never money ("2 eggs").
    if (!hasCurrency && value < 10 && !_spendVerb.hasMatch(before)) continue;
    // "buy 12 eggs": a number between a buying word and a thing is a count.
    if (!hasCurrency &&
        _quantity.hasMatch(before) &&
        _thingAfter.hasMatch(after)) {
      continue;
    }
    if (m.namedGroup('k') != null) {
      number = (value * 1000).toStringAsFixed(value * 1000 % 1 == 0 ? 0 : 2);
    }
    final income = _incomeVerb.hasMatch(clause);
    final note = _describe(clause, m);
    out.add(
      VoiceSpend(
        amount: number,
        note: note,
        category: income
            ? (RegExp(
                    r'\b(?:salary|sweldo|payday)\b',
                    caseSensitive: false,
                  ).hasMatch(clause)
                  ? 'Salary'
                  : 'Income')
            : categoryFor(clause),
        type: income ? 'income' : 'expense',
      ),
    );
  }
  return out;
}

String _describe(String clause, RegExpMatch m) {
  var s = clause.replaceRange(m.start, m.end, ' ');
  s = s.replaceAll(
    RegExp(
      r"\b(?:i\s+)?(?:just\s+)?(?:spent|spend|paid|pay|bought|got paid|received|earned|cost|costs|it was|was|worth|about|around|like|for|on|pesos?|php|bucks|dollars?|usd|um+|uh+|so|okay|today|yesterday)\b",
      caseSensitive: false,
    ),
    ' ',
  );
  s = s
      .replaceAll(RegExp(r"[₱$,.;!?]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // "at Jollibee" reads better than a dangling "at".
  s = s.replaceFirst(
    RegExp(r'^(?:at|the|a|an|and)\s+', caseSensitive: false),
    '',
  );
  s = s.replaceFirst(
    RegExp(r'\s+(?:at|the|a|an|and)$', caseSensitive: false),
    '',
  );
  if (s.isEmpty) return '';
  return s[0].toUpperCase() + s.substring(1);
}

// ── categories ────────────────────────────────────────────────────────────

const _categoryWords = <String, List<String>>{
  'Food': [
    'lunch',
    'dinner',
    'breakfast',
    'brunch',
    'snack',
    'snacks',
    'coffee',
    'cafe',
    'food',
    'meal',
    'pizza',
    'burger',
    'jollibee',
    'mcdo',
    'mcdonalds',
    'starbucks',
    'milk tea',
    'milktea',
    'restaurant',
    'eat',
    'takeout',
    'delivery',
    'foodpanda',
    'grabfood',
    'drinks',
    'beer',
  ],
  'Transport': [
    'grab',
    'taxi',
    'uber',
    'angkas',
    'joyride',
    'gas',
    'fuel',
    'petrol',
    'parking',
    'toll',
    'bus',
    'train',
    'mrt',
    'lrt',
    'tricycle',
    'car',
  ],
  'Pamasahe': ['jeep', 'jeepney', 'fare', 'pamasahe'],
  'Groceries': [
    'groceries',
    'grocery',
    'supermarket',
    'puregold',
    'sm market',
    'savemore',
    'eggs',
    'rice',
    'vegetables',
    'fruit',
  ],
  'Merkado': ['palengke', 'market', 'merkado'],
  'Kuryente': ['electric', 'electricity', 'meralco', 'kuryente', 'power bill'],
  'Tubig': ['water bill', 'tubig', 'maynilad', 'manila water'],
  'Load': ['load', 'prepaid', 'gcash load', 'data'],
  'Padala': ['padala', 'remittance', 'sent to', 'send money'],
  'Bills': [
    'bill',
    'bills',
    'rent',
    'internet',
    'wifi',
    'subscription',
    'netflix',
    'spotify',
    'insurance',
    'phone bill',
    'postpaid',
  ],
  'Health': [
    'medicine',
    'pharmacy',
    'mercury',
    'doctor',
    'clinic',
    'dentist',
    'hospital',
    'vitamins',
    'checkup',
  ],
  'Entertainment': ['movie', 'cinema', 'concert', 'game', 'games', 'tickets'],
  'Shopping': [
    'shopping',
    'shoes',
    'shirt',
    'clothes',
    'lazada',
    'shopee',
    'mall',
    'gift',
    'book',
    'books',
  ],
};

/// The best category for [text], or 'Other'.
String categoryFor(String text) {
  final low = ' ${text.toLowerCase()} ';
  // Longest keyword wins, so "water bill" beats "bill".
  String best = 'Other';
  var bestLen = 0;
  _categoryWords.forEach((category, words) {
    for (final w in words) {
      if (w.length > bestLen &&
          RegExp('(?<![a-z])${RegExp.escape(w)}(?![a-z])').hasMatch(low)) {
        best = category;
        bestLen = w.length;
      }
    }
  });
  return best;
}

// ── spoken numbers ────────────────────────────────────────────────────────

const _units = {
  'zero': 0,
  'one': 1,
  'a': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};
const _tens = {
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};

final _numberRun = RegExp(
  r"\b(?:(?:zero|one|a|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|and)(?:[\s-]+|$))+",
  caseSensitive: false,
);

/// Number words to digits: "two hundred fifty" → "250", "fifteen hundred"
/// → "1500", "three thousand" → "3000", "1.5k" → "1500". Runs that are not
/// a number ("a", "and" alone) are left as they are.
String wordsToDigits(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'\b(\d+(?:\.\d+)?)\s?k\b', caseSensitive: false),
    (m) {
      final v = double.parse(m[1]!) * 1000;
      return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);
    },
  );
  out = out.replaceAllMapped(_numberRun, (m) {
    final raw = m[0]!;
    final words = raw
        .toLowerCase()
        .split(RegExp(r'[\s-]+'))
        .where((w) => w.isNotEmpty && w != 'and')
        .toList();
    // Needs a real number word, not just "a".
    if (words.isEmpty || words.every((w) => w == 'a')) return raw;
    if (!words.any(
      (w) =>
          w != 'a' &&
          (_units.containsKey(w) ||
              _tens.containsKey(w) ||
              w == 'hundred' ||
              w == 'thousand'),
    )) {
      return raw;
    }
    var total = 0;
    var current = 0;
    var seen = false;
    for (final w in words) {
      if (_units.containsKey(w)) {
        current += _units[w]!;
        seen = true;
      } else if (_tens.containsKey(w)) {
        current += _tens[w]!;
        seen = true;
      } else if (w == 'hundred') {
        current = (current == 0 ? 1 : current) * 100;
        seen = true;
      } else if (w == 'thousand') {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
        seen = true;
      } else {
        return raw;
      }
    }
    if (!seen) return raw;
    // Keep the trailing space/hyphen the run swallowed.
    final trail = RegExp(r'[\s-]+$').firstMatch(raw)?[0] ?? '';
    return '${total + current}$trail';
  });
  return out;
}
