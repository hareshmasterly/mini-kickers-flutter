import 'dart:math';

import 'package:mini_kickers/data/models/remote_avatar.dart';
import 'package:mini_kickers/data/services/avatar_service.dart';

/// Generates kid-friendly random handles like "BraveTiger47" + matching
/// avatar id. Pool size: 32 adjectives × N avatars × 990 numbers
/// (currently ~380k combinations with the default catalog).
///
/// The animal pool is now sourced from [AvatarService] so editors can
/// add/remove avatars in Firestore without an app update. The avatar
/// chosen by [generate] also drives the matching avatar id on the
/// `users/{uid}` profile, so visual cohesion is automatic — if your
/// handle is "QuickFox42", your avatar starts as a fox.
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

  /// One generated bundle: handle + display name (handle minus number)
  /// + avatar id. Returned together so the caller never has to
  /// re-derive the avatar from the handle string.
  ///
  /// The animal pool is read from [AvatarService.defaults]. If the
  /// service hasn't initialised yet (or every avatar has
  /// `is_default: false`), falls back to "Tiger" so generation never
  /// throws.
  static GeneratedHandle generate() {
    final List<RemoteAvatar> pool = AvatarService.instance.defaults;
    final RemoteAvatar avatar = pool.isEmpty
        ? const RemoteAvatar(
            id: 'tiger', displayName: 'Tiger', emoji: '🐯')
        : pool[_rng.nextInt(pool.length)];

    final String adj = adjectives[_rng.nextInt(adjectives.length)];
    // Use the avatar's display name (capitalised) in the handle so
    // "QuickFox" reads naturally. Strip spaces — display names like
    // "Striker Panda" become "StrikerPanda" in the handle but stay
    // "Striker Panda" in the displayName field.
    final String animalForHandle = avatar.displayName.replaceAll(' ', '');
    final int n = 10 + _rng.nextInt(990); // 10..999

    return GeneratedHandle(
      handle: '$adj$animalForHandle$n',
      displayName: '$adj ${avatar.displayName}',
      avatarId: avatar.id,
    );
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

  /// Unique handle stored in Firestore — adjective+animal+number, no
  /// spaces. Used as the canonical identifier in the `handles/`
  /// uniqueness collection.
  final String handle;

  /// Human-readable form for UI ("Brave Tiger" instead of
  /// "BraveTiger47"). The number is dropped here because it's only
  /// needed to disambiguate; in conversation the player is just
  /// "Brave Tiger".
  final String displayName;

  /// Avatar id (matches one of [HandleGenerator.animals]).
  final String avatarId;
}
