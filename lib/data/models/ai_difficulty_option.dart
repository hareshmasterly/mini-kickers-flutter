import 'package:mini_kickers/data/models/game_models.dart';

/// One row in the difficulty picker, sourced from the Firestore
/// `ai_settings.ai_difficulty_levels` array.
///
/// Schema (per array entry):
///   • `id` — required string. Must match an [AiDifficulty] value
///     (`easy` / `medium` / `hard`); rows with unknown ids are dropped.
///   • `name` — optional display name (e.g. "Beginner"). Falls back to
///     a capitalised version of the id.
///   • `subtitle` — optional one-line tagline (e.g. "Just learning?
///     Start here.").
///   • `emoji` — optional decorative emoji (🌱 / ⚖️ / 🔥).
///
/// The [SettingsService] exposes a fully resolved
/// `availableAiDifficulties` getter that handles fallback to a
/// hardcoded default list when the remote array is missing or empty.
class AiDifficultyOption {
  const AiDifficultyOption({
    required this.id,
    required this.name,
    this.subtitle,
    this.emoji,
  });

  final AiDifficulty id;
  final String name;
  final String? subtitle;
  final String? emoji;

  /// Returns `null` for entries with an unrecognised `id` so the caller
  /// can drop them — defends the picker against typos in Firestore.
  static AiDifficultyOption? fromMap(final Map<String, dynamic> raw) {
    final AiDifficulty? id = AiDifficultyX.fromId(raw['id'] as String?);
    if (id == null) return null;
    final String name = (raw['name'] as String?)?.trim().isNotEmpty == true
        ? (raw['name'] as String).trim()
        : _defaultNameFor(id);
    final String? subtitle = (raw['subtitle'] as String?)?.trim();
    final String? emoji = (raw['emoji'] as String?)?.trim();
    return AiDifficultyOption(
      id: id,
      name: name,
      subtitle: (subtitle?.isEmpty ?? true) ? null : subtitle,
      emoji: (emoji?.isEmpty ?? true) ? null : emoji,
    );
  }

  static String _defaultNameFor(final AiDifficulty d) {
    switch (d) {
      case AiDifficulty.easy:
        return 'Easy';
      case AiDifficulty.medium:
        return 'Medium';
      case AiDifficulty.hard:
        return 'Hard';
    }
  }

  /// Shipped as a last-resort fallback when Firestore is unreachable on
  /// a brand-new install AND no cached snapshot exists. Mirrors the
  /// initial values you'd seed into the `ai_difficulty_levels` array.
  static const List<AiDifficultyOption> fallback = <AiDifficultyOption>[
    AiDifficultyOption(
      id: AiDifficulty.easy,
      name: 'Beginner',
      subtitle: 'Just learning? Start here.',
      emoji: '🌱',
    ),
    AiDifficultyOption(
      id: AiDifficulty.medium,
      name: 'Pro',
      subtitle: 'A fair fight.',
      emoji: '⚖️',
    ),
    AiDifficultyOption(
      id: AiDifficulty.hard,
      name: 'Champion',
      subtitle: 'Bring your A-game.',
      emoji: '🔥',
    ),
  ];
}
