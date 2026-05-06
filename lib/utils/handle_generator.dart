import 'dart:math';

import 'package:mini_kickers/data/models/remote_avatar.dart';
import 'package:mini_kickers/data/services/avatar_service.dart';

/// Generates kid-friendly handles plus a matching display name and a
/// random avatar.
///
/// **Avatar/handle decoupling**: random handles use *football roles*
/// (Striker, Goalkeeper, …) rather than the chosen avatar's animal
/// name. This way the user can swap avatars freely without producing
/// the awkward "BraveTiger47 + Fox face" mismatch. The avatar id
/// returned alongside the handle is just an initial pick — the user
/// can change it independently.
///
/// **Two paths**:
///   • [generate] — random "Adjective + Role + Number" (e.g.
///     "BraveStriker47") for users who skip personalisation.
///   • [fromName] — "Name + Number" (e.g. "Aarav847") when the user
///     types their first name into the welcome card.
class HandleGenerator {
  HandleGenerator._();

  static final Random _rng = Random();

  /// Kid-friendly adjectives — no negative or judgmental words. Tested
  /// against typical 9+ vocabulary so handles always feel positive.
  static const List<String> adjectives = <String>[
    'Brave', 'Quick', 'Lucky', 'Wild', 'Mighty', 'Sneaky', 'Happy',
    'Bold', 'Cool', 'Speedy', 'Clever', 'Swift', 'Fierce', 'Daring',
    'Sunny', 'Funky', 'Jazzy', 'Zippy', 'Snappy', 'Lively', 'Cheery',
    'Witty', 'Frosty', 'Royal', 'Stellar', 'Cosmic', 'Sparkly',
    'Turbo', 'Mega', 'Super', 'Epic', 'Legend',
  ];

  /// Football-themed roles — used in random handles so they read
  /// naturally ("BraveStriker47", "QuickKicker92") and stay decoupled
  /// from the picked avatar.
  static const List<String> roles = <String>[
    'Striker', 'Kicker', 'Champion', 'Player', 'Captain', 'Goalkeeper',
    'Defender', 'Midfielder', 'Winger', 'Hero', 'Star', 'Ace',
    'Pro', 'Master', 'Wizard', 'Legend',
  ];

  /// Random "Adjective + Role + Number" handle. Avatar is chosen
  /// independently from [AvatarService.defaults] so the user can
  /// freely swap it without affecting the handle text.
  static GeneratedHandle generate() {
    final String adj = adjectives[_rng.nextInt(adjectives.length)];
    final String role = roles[_rng.nextInt(roles.length)];
    final int n = 10 + _rng.nextInt(990); // 10..999
    return GeneratedHandle(
      handle: '$adj$role$n',
      displayName: '$adj $role',
      avatarId: _pickRandomAvatarId(),
    );
  }

  /// "FirstName + Number" handle (e.g. "Aarav847"). Falls back to
  /// [generate] if [name] sanitises to empty so we never persist a
  /// blank profile.
  ///
  /// Avatar is preserved from [keepAvatarId] when supplied — used by
  /// the welcome card so typing a name doesn't reset the user's
  /// avatar pick.
  static GeneratedHandle fromName(
    final String name, {
    final String? keepAvatarId,
  }) {
    final String cleaned = sanitizeName(name);
    if (cleaned.isEmpty) {
      // No usable letters — fall back to the random path. Reuses the
      // existing avatar if the caller passed one in.
      final GeneratedHandle random = generate();
      return GeneratedHandle(
        handle: random.handle,
        displayName: random.displayName,
        avatarId: keepAvatarId ?? random.avatarId,
      );
    }
    final int n = 10 + _rng.nextInt(990);
    return GeneratedHandle(
      handle: '$cleaned$n',
      displayName: cleaned,
      avatarId: keepAvatarId ?? _pickRandomAvatarId(),
    );
  }

  /// Strips non-letter characters, caps length at 12, and applies
  /// "Title Case" so "aarav  KUMAR!" → "AaravKumar".
  static String sanitizeName(final String name) {
    final String letters = name.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return '';
    final String capped =
        letters.length > 12 ? letters.substring(0, 12) : letters;
    return capped[0].toUpperCase() + capped.substring(1).toLowerCase();
  }

  static String _pickRandomAvatarId() {
    final List<RemoteAvatar> pool = AvatarService.instance.defaults;
    if (pool.isEmpty) return 'tiger';
    return pool[_rng.nextInt(pool.length)].id;
  }

  /// Returns the emoji for an avatar id by consulting [AvatarService]
  /// first (so editor-added avatars show their configured emoji), then
  /// falling back to a generic soccer ball glyph.
  static String emojiFor(final String avatarId) {
    final RemoteAvatar? avatar = AvatarService.instance.findById(avatarId);
    return avatar?.emoji ?? '⚽';
  }
}

class GeneratedHandle {
  const GeneratedHandle({
    required this.handle,
    required this.displayName,
    required this.avatarId,
  });

  /// Unique handle stored in Firestore. Random path: "BraveStriker47".
  /// Name path: "Aarav847". Used as the canonical identifier in the
  /// `handles/` uniqueness collection.
  final String handle;

  /// Human-readable form for UI ("Brave Striker" or "Aarav"). The
  /// number is dropped here because it's only needed to disambiguate;
  /// in conversation the player is just "Brave Striker".
  final String displayName;

  /// Avatar id — chosen independently from the handle so swapping
  /// avatars never produces a name/face mismatch.
  final String avatarId;
}
