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
  // Not part of a clock time ("9:15") or a decimal.
  r"(?<![\w.:])(?:(?<pre>₱|php|p|\$|usd|us\$)\s?)?"
  r"(?<num>\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"
  r"(?<k>k\b)?"
  r"(?:\s?(?<post>pesos?|php|bucks|dollars?|usd))?(?![\w])",
  caseSensitive: false,
);

/// Words that make a number a time, a date or a count, not money.
final _notMoneyAfter = RegExp(
  r"^\s*(?:am|pm|a\.m|p\.m|o'?clock|minutes?|mins?|hours?|hrs?|days?|nights?|weeks?|months?|years?|kids?|adults?|pax|persons?|guests?|times|percent|%|st\b|nd\b|rd\b|th\b|kilos?|kg|km|people|items?|pieces?|pcs)",
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
final _notSpent = RegExp(
  r"\b(?:need|needs|needed|bring|prepare|save|saving|budget|owe|owes|borrow|lend|lent|ask(?:ed)? for)\b",
  caseSensitive: false,
);
final _spentWord = RegExp(
  r"\b(?:spent|paid|bought|cost|costs|got paid|received|earned)\b",
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
  final found = <(RegExpMatch, String)>[];
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
    // "bought one for 450", "2 at 99 each": a count, the price comes next.
    if (RegExp(
      r'^\s*(?:pcs?|pieces?|x)?\s*(?:for|at|@)\s*(?:₱|php|\$)?\s*\d',
      caseSensitive: false,
    ).hasMatch(after)) {
      continue;
    }
    // "9:15": the hour of a clock time.
    if (after.startsWith(':')) continue;
    // "they need 200 pesos", "I owe Sam 500": money mentioned, not spent.
    if (_notSpent.hasMatch(before) && !_spentWord.hasMatch(clause)) continue;
    var number = m.namedGroup('num')!.replaceAll(',', '');
    final value = double.tryParse(number);
    if (value == null || value <= 0) continue;
    // A bare single digit with no currency is almost never money ("2 eggs").
    // A bare single digit is almost never money ("2 eggs", "on the 3rd, 2
    // nights") unless a real spending word comes right before it.
    if (!hasCurrency && value < 10 && !_spentWord.hasMatch(before)) continue;
    // "buy 12 eggs": a number between a buying word and a thing is a count.
    if (!hasCurrency &&
        _quantity.hasMatch(before) &&
        _thingAfter.hasMatch(after)) {
      continue;
    }
    if (m.namedGroup('k') != null) {
      number = (value * 1000).toStringAsFixed(value * 1000 % 1 == 0 ? 0 : 2);
    }
    found.add((m, number));
  }

  // Each amount gets its own slice of the clause, so "spent 250 for
  // foodpanda and I spent 465 for chicken" gives two descriptions, not two
  // copies of the whole sentence.
  final out = <VoiceSpend>[];
  var start = 0;
  for (var i = 0; i < found.length; i++) {
    final (m, number) = found[i];
    final end = i + 1 < found.length
        ? _boundary(clause, m.end, found[i + 1].$1.start)
        : clause.length;
    final span = clause.substring(start, end);
    final local = m.start - start;
    final income = _incomeVerb.hasMatch(span);
    out.add(
      VoiceSpend(
        amount: number,
        note: _describe(span, local, local + (m.end - m.start)),
        category: income
            ? (RegExp(
                    r'\b(?:salary|sweldo|payday)\b',
                    caseSensitive: false,
                  ).hasMatch(span)
                  ? 'Salary'
                  : 'Income')
            : categoryFor(span),
        type: income ? 'income' : 'expense',
      ),
    );
    start = end;
  }
  return out;
}

/// "… and I spent …" starts the next entry.
final _nextSpend = RegExp(
  r"(?:[,;.]\s*)?\b(?:and\s+)?(?:then\s+)?(?:i\s+)?(?:also\s+)?(?:just\s+)?(?:spent|paid|bought|got paid|received|earned)\b",
  caseSensitive: false,
);
final _separator = RegExp(
  r"[,;.]|\b(?:and|then|plus|also)\b",
  caseSensitive: false,
);

/// Where the text between two amounts splits: before the next spending
/// verb, else at the last comma or "and", else right after the first
/// amount ("lunch 250 coffee 120").
int _boundary(String clause, int from, int to) {
  final gap = clause.substring(from, to);
  final verb = _nextSpend.firstMatch(gap);
  if (verb != null) return from + verb.start;
  final seps = _separator.allMatches(gap).toList();
  if (seps.isNotEmpty) return from + seps.last.start;
  return from;
}

/// Words that say nothing about what the money was for.
final _noise = RegExp(
  r"\b(?:hey|hi|hello|okay|ok|so|um+|uh+|er+|like|basically|actually|really|just|i|i've|i'm|we|spent|spend|paid|pay|bought|got paid|received|earned|cost|costs|it was|was|worth|about|around|roughly|approximately|more or less|pesos?|php|bucks|dollars?|usd|today|yesterday|earlier|kanina|this morning|this afternoon|this evening|tonight|last night)\b",
  caseSensitive: false,
);

/// Connectors that only dangle at the edges ("for Jollibee", "lunch at").
final _edge = RegExp(
  r"^(?:at|the|a|an|and|then|also|plus|for|on|to|from|with|in)\s+|\s+(?:at|the|a|an|and|then|also|plus|for|on|to|from|with|in)$",
  caseSensitive: false,
);

String _describe(String span, int amountStart, int amountEnd) {
  var s = span.replaceRange(amountStart, amountEnd, ' ');
  // Any other amount left in the slice is not part of the description.
  s = s.replaceAll(_amount, ' ').replaceAll(_noise, ' ');
  s = s
      .replaceAll(RegExp(r"[₱$,.;!?]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  String prev;
  do {
    prev = s;
    s = s.replaceAll(_edge, '').trim();
  } while (s != prev);
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
    'food panda',
    'potato corner',
    'chicken',
    'chooks',
    'inasal',
    'mang inasal',
    'chowking',
    'kfc',
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
