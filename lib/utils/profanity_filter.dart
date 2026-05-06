/// Tiny starter banned-word list for the welcome-card name input.
///
/// Goal: catch the obvious cases that would embarrass the app on
/// review. Comprehensive moderation isn't possible client-side and
/// shouldn't be attempted — this is a "first line of defense" only.
/// Production hardening (regional slurs, leet-speak, fuzzy matching)
/// belongs server-side once the Blaze plan is enabled and a Cloud
/// Function can validate handles before reservation.
///
/// **Editing the list**: keep entries lowercased and stripped of
/// non-letters; matching does the same to the input. Add common
/// English + Hindi/Hinglish slurs and the obvious 4-letter words.
class ProfanityFilter {
  ProfanityFilter._();

  /// Returns true when [name] contains a banned substring after
  /// normalisation (lowercased, non-letters stripped).
  ///
  /// Substring (not whole-word) match — catches "asss" inside
  /// "passsword" too, which is intentional for a kids audience even
  /// though it false-positives "class" if "ass" is on the list. The
  /// list below is deliberately picked to avoid common false
  /// positives; tune if user reports come in.
  static bool isBlocked(final String name) {
    final String normalised =
        name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (normalised.isEmpty) return false;
    for (final String w in _banned) {
      if (normalised.contains(w)) return true;
    }
    return false;
  }

  /// Lower-case substrings to block. Each entry should be ≥ 4 chars
  /// where possible to avoid colliding with normal names.
  static const List<String> _banned = <String>[
    // Generic English slurs / strong profanity (4+ chars only — 3-char
    // words like "ass" / "tit" produce too many false positives in
    // ordinary names so we omit them and rely on context).
    'fuck',
    'shit',
    'bitch',
    'bastard',
    'cunt',
    'dick',
    'cock',
    'penis',
    'vagina',
    'pussy',
    'whore',
    'slut',
    'rape',
    'nazi',
    // Hindi / Hinglish — common informal slurs that would be
    // recognisable in Indian schools. Lower-case roman transliterations.
    'chutiya',
    'chutia',
    'gandu',
    'gaandu',
    'madarchod',
    'madrchod',
    'bhenchod',
    'behenchod',
    'bhosdi',
    'bhosadi',
    'lavda',
    'lawda',
    'lund',
    'randi',
    'haraami',
    'harami',
    // Common slurs / hate terms.
    'nigger',
    'faggot',
    'retard',
  ];
}
