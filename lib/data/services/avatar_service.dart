import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/remote_avatar.dart';

/// Centralised access to the editor-curated avatar catalog from the
/// `avatars/` Firestore collection.
///
/// Lifecycle:
///   1. [main] calls [init] once after Firebase boot — fetches the
///      catalog and caches in memory.
///   2. [HandleGenerator] consults [defaults] when generating new
///      handles (random pool).
///   3. [WelcomeCard] consults [all] for the picker.
///   4. If the Firestore fetch fails (offline first launch, network
///      error), [_fallback] kicks in with the same 12 animals that
///      used to be hardcoded — so the UI never has zero options.
///
/// Thread-safety: the singleton's caches are written exclusively by
/// [init] and never mutated afterwards (immutable list of immutable
/// avatars), so reads from any isolate are safe without locking.
class AvatarService extends ChangeNotifier {
  AvatarService._();

  static final AvatarService instance = AvatarService._();

  static const String _collection = 'avatars';

  List<RemoteAvatar> _avatars = const <RemoteAvatar>[];

  /// All avatars whose `enabled` flag is true, sorted by `order`.
  /// Drives the welcome-card / edit-profile picker.
  List<RemoteAvatar> get all =>
      _avatars.where((final RemoteAvatar a) => a.enabled).toList();

  /// Subset of [all] that's also marked `is_default: true` — used by
  /// [HandleGenerator] as the random pool. Lets editors add "premium"
  /// or seasonal avatars to the picker WITHOUT them being randomly
  /// auto-assigned to new users.
  List<RemoteAvatar> get defaults => all
      .where((final RemoteAvatar a) => a.isDefault)
      .toList();

  /// Look up by id. Falls back to the first available avatar if the
  /// id is unknown (e.g. an admin removed the avatar after a user
  /// already had it). Returns null only if there are zero avatars.
  RemoteAvatar? findById(final String id) {
    final Iterable<RemoteAvatar> match =
        _avatars.where((final RemoteAvatar a) => a.id == id);
    if (match.isNotEmpty) return match.first;
    return all.isNotEmpty ? all.first : null;
  }

  /// Bootstrap. Idempotent — subsequent calls re-fetch (useful after
  /// a remote-config push) but won't double-init.
  Future<void> init() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection(_collection).get();
      if (snap.docs.isEmpty) {
        if (kDebugMode) {
          debugPrint('AvatarService: empty catalog, using fallback');
        }
        _avatars = _fallback;
      } else {
        final List<RemoteAvatar> parsed = snap.docs
            .map((final QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                RemoteAvatar.fromMap(d.id, d.data()))
            .toList()
          // Sort by order; ties broken by display_name for stability.
          ..sort((final RemoteAvatar a, final RemoteAvatar b) {
            final int byOrder = a.order.compareTo(b.order);
            return byOrder != 0
                ? byOrder
                : a.displayName.compareTo(b.displayName);
          });
        _avatars = parsed;
        if (kDebugMode) {
          debugPrint('AvatarService: loaded ${_avatars.length} avatars');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('AvatarService: fetch failed → $e (using fallback)');
      }
      _avatars = _fallback;
    }
    notifyListeners();
  }

  /// Hardcoded fallback used on first launch with no network or when
  /// the Firestore fetch fails. Mirrors the 12 animals from the
  /// original [HandleGenerator.avatarEmoji] map so the picker always
  /// has options even offline.
  static const List<RemoteAvatar> _fallback = <RemoteAvatar>[
    RemoteAvatar(id: 'tiger', displayName: 'Tiger', emoji: '🐯', order: 1),
    RemoteAvatar(id: 'bear', displayName: 'Bear', emoji: '🐻', order: 2),
    RemoteAvatar(id: 'fox', displayName: 'Fox', emoji: '🦊', order: 3),
    RemoteAvatar(id: 'lion', displayName: 'Lion', emoji: '🦁', order: 4),
    RemoteAvatar(id: 'wolf', displayName: 'Wolf', emoji: '🐺', order: 5),
    RemoteAvatar(id: 'eagle', displayName: 'Eagle', emoji: '🦅', order: 6),
    RemoteAvatar(id: 'hawk', displayName: 'Hawk', emoji: '🦅', order: 7),
    RemoteAvatar(id: 'owl', displayName: 'Owl', emoji: '🦉', order: 8),
    RemoteAvatar(id: 'panda', displayName: 'Panda', emoji: '🐼', order: 9),
    RemoteAvatar(id: 'rabbit', displayName: 'Rabbit', emoji: '🐰', order: 10),
    RemoteAvatar(
        id: 'dolphin', displayName: 'Dolphin', emoji: '🐬', order: 11),
    RemoteAvatar(id: 'shark', displayName: 'Shark', emoji: '🦈', order: 12),
  ];
}
