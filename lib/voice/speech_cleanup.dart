/// Takes the speech out of a transcript before it is shaped: hesitations
/// ("um", "uh"), greetings ("hey", "okay so"), verbal tics ("like",
/// "basically", "you know") and stutters ("hey hey"). The words that
/// carry meaning stay exactly as said; only the noise goes.
///
/// Used for everything that ends up in a note, a list or a money entry,
/// whichever shaper produced it. The editable transcript keeps every word.
String cleanSpeech(String text) {
  var s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return s;

  // Hesitations anywhere: "um", "uhh", "erm", "hmm", with a trailing comma.
  s = s.replaceAll(_hesitation, ' ');

  // Stutters: "hey hey", "the the". "had had" and "that that" can be real.
  s = s.replaceAllMapped(
    RegExp(r"\b([\w']+)(?:[\s,]+\1\b)+", caseSensitive: false),
    (m) => _keepDouble.contains(m[1]!.toLowerCase()) ? m[0]! : m[1]!,
  );

  // "you know" / "I mean" / "I guess" as asides, not as the point.
  s = s.replaceAll(_aside, ' ');

  // "like" as a tic: "I like need to", "like five kilos", "so like".
  // Kept as a verb or comparison: "I like coffee", "looks like rain".
  s = s.replaceAllMapped(_likeTic, (m) => m[1] ?? m[2] ?? '');

  // Talking to the app: "can you remind me to…" is "remind me to…", and
  // "I just realized I have to…" is "I have to…".
  s = s.replaceAll(_politeAsk, 'remind me');
  s = s.replaceAll(_realized, '');

  // "basically", "literally" and friends add nothing to a note.
  s = s.replaceAll(_tic, ' ');

  // Greetings and run-ups at the start of the memo or of a sentence:
  // "Hey Typed, okay so…", "Alright so…", "So yeah…".
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  String prev;
  do {
    prev = s;
    s = s.replaceAllMapped(_opener, (m) => m[1]!);
  } while (s != prev);

  return s
      .replaceAllMapped(RegExp(r'\s+([,.!?;])'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'([,;])(?:\s*[,;])+'), (m) => m[1]!)
      .replaceAll(RegExp(r'(^|[.!?]\s+)[,;]\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[,;.\s]+'), '')
      .trim();
}

const _keepDouble = {'had', 'that', 'is', 'very', 'bye', 'no'};

final _hesitation = RegExp(
  r"\b(?:u+m+|u+h+|uhm+|e+r+m+|e+r{2,}|h+m+|mhm+|a+h+)\b,?",
  caseSensitive: false,
);

final _aside = RegExp(
  r"(?:,\s*|\b)(?:you know|i mean|i guess|you see)(?=\s*(?:[,.!?;]|$))"
  r"|(?<=^|[,.!?;]\s*)(?:you know|i mean)\s*,?\s+",
  caseSensitive: false,
);

// Group 1 keeps what came before the tic.
final _likeTic = RegExp(
  // "I like need to…": between a pronoun and what they need to do.
  r"(\b(?:i|we|you|they|he|she)\s+)like\b,?\s*"
  r"(?=(?:need|needs|have|has|had|want|wanted|gotta|should|must|really|totally|just|maybe|also|went|got|spent|paid|bought|forgot)\b)"
  // "so like…", "and like five kilos", "like, maybe": a filler, not a verb.
  r"|(^|[,.!?;]\s*|\b(?:so|and|but|was|um|uh|yeah|then|also|thinking|or)\s+)like\b,?\s*"
  r"(?=(?:i|we|you|they|maybe|so|um|uh|a|an|the|this|that|my|our|\d|one|two|three|four|five|six|seven|eight|nine|ten|twenty|fifty|hundred|around|about|really|totally|super|just|also|then|need|have|want|gotta)\b|[,.!?;]|$)",
  caseSensitive: false,
);

final _politeAsk = RegExp(
  r"\b(?:(?:can|could|would|will)\s+you\s+)?(?:please\s+)?remind\s+me(?:\s+please)?(?=\s+(?:to|about)\b)",
  caseSensitive: false,
);

final _realized = RegExp(
  r"\b(?:i\s+)?(?:just\s+)?(?:realized|realised|remembered)(?:\s+that)?,?\s+(?=(?:i|we)\s+(?:have|need|gotta|should|must|still)\b|(?:i'll|i'm)\b)",
  caseSensitive: false,
);

final _tic = RegExp(
  r"\b(?:basically|literally|honestly|kinda like|sort of like),?(?=\s|$)",
  caseSensitive: false,
);

final _opener = RegExp(
  r"(^|[.!?]\s+)(?:"
  // Always a run-up at the start: "Hey Typed,", "Okay so", "Alright".
  r"(?:hey|hi|hello|yo|okay|ok|alright|all right|and so)(?:\s+typed)?\b[\s,]*"
  // "So the meeting…" → "The meeting…", but not "So many…".
  r"|(?:so\s+yeah|yeah\s+so)\b[\s,]*"
  r"|so\b(?!\s+(?:many|much|far|long|good|bad|that)\b)[\s,]*"
  // Only with a comma or a following "so": "Well, …", "Yeah so…" — not
  // "Well done", "Right after lunch".
  r"|(?:yeah|well|oh|right|anyway)(?:,\s*|\s+(?=so\b))"
  r")(?=\S)",
  caseSensitive: false,
);
