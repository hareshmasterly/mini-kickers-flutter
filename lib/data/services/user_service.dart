import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:mini_kickers/data/models/user_profile.dart';
import 'package:mini_kickers/utils/handle_generator.dart';

/// Per-install user identity.
///
/// Lifecycle:
///   1. App launch → [init] runs anonymous sign-in (instant — no UI)
///      and gives this install a stable Firebase Auth `uid`.
///   2. [init] then loads `users/{uid}` from Firestore. If absent,
///      we GENERATE a handle but DON'T save yet — the welcome card
///      shown on the home screen lets the user accept or re-roll
///      before persisting. [isFirstLaunch] reflects this state.
///   3. The welcome card calls [confirmProfile] (current pending
///      handle) or [reroll] (try a different handle/avatar).
///   4. After confirmation, every app launch updates `last_seen_at`
///      so Firebase Auth's 30-day inactivity auto-cleanup knows
///      we're still active.
///
/// Data deletion is handled SERVER-SIDE: Firebase Auth auto-deletes
/// inactive anonymous accounts after 30 days, and our Cloud Function
/// `onUserDeleted` cleans up the matching `users/{uid}` doc + the
/// `handles/{handle_lower}` reservation. The client never deletes —
/// it just trusts the server lifecycle.
class UserService extends ChangeNotifier {
  UserService._();

  static final UserService instance = UserService._();

  static const String _usersCollection = 'users';
  static const String _handlesCollection = 'handles';

  /// Minimum interval between handle changes — prevents abuse and
  /// gives the uniqueness system breathing room. Mirrors the rate
  /// limit advertised in the Settings → Edit Profile UI.
  static const Duration handleChangeCooldown = Duration(days: 7);

  /// How long a profile lives after the last app open before
  /// Firestore's TTL policy auto-deletes it. Pushed forward by 30
  /// days on every successful app launch (see [_touchLastSeen]). The
  /// matching TTL policy must be configured ONCE in the Firebase
  /// Console: Firestore → TTL → add policy on `users` collection
  /// with field `ttl`, and same on `handles` collection.
  static const Duration profileTtl = Duration(days: 30);

  /// Returns a Firestore [Timestamp] [profileTtl] from now — the
  /// cutoff after which Firestore's TTL service will delete the doc
  /// if it isn't refreshed.
  Timestamp get _futureTtl => Timestamp.fromDate(
        DateTime.now().add(profileTtl),
      );

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _uid;
  UserProfile? _profile;
  GeneratedHandle? _pendingHandle;

  /// Stable Firebase Auth uid for this install. Null until [init]
  /// completes successfully.
  String? get uid => _uid;

  /// The persisted profile from Firestore. Null until [confirmProfile]
  /// runs for the first time on a fresh install.
  UserProfile? get profile => _profile;

  /// Pending handle shown on the welcome card before the user taps
  /// "That's me!". Null after [confirmProfile] or on returning users.
  GeneratedHandle? get pendingHandle => _pendingHandle;

  /// True when this install has no saved profile yet — the welcome
  /// card on the home screen reads this and shows itself only when
  /// it's true. Flips to false once [confirmProfile] succeeds.
  bool get isFirstLaunch => _profile == null;

  /// Bootstrap: anonymous sign-in + load-or-generate profile.
  /// Idempotent. Call once from [main]; subsequent calls are no-ops.
  Future<void> init() async {
    if (_uid != null) return;
    try {
      // 1. Anonymous sign-in. Returns immediately if already signed in.
      User? user = _auth.currentUser;
      user ??= (await _auth.signInAnonymously()).user;
      if (user == null) {
        if (kDebugMode) debugPrint('UserService: anon sign-in returned null');
        return;
      }
      _uid = user.uid;
      if (kDebugMode) debugPrint('UserService: uid=$_uid');

      // 2. Load existing profile from Firestore.
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await _db.collection(_usersCollection).doc(_uid).get();
      if (snap.exists) {
        _profile = UserProfile.fromMap(_uid!, snap.data()!);
        if (kDebugMode) {
          debugPrint('UserService: loaded existing profile '
              '${_profile!.handle}');
        }
        // Returning user — bump last_seen_at, fire-and-forget.
        unawaited(_touchLastSeen());
      } else {
        // 3. New install — generate a pending handle for the welcome
        //    card to display. NOT persisted yet; user must accept.
        _pendingHandle = HandleGenerator.generate();
        if (kDebugMode) {
          debugPrint('UserService: new install, pending handle '
              '${_pendingHandle!.handle}');
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('UserService: init failed (non-fatal) → $e\n$st');
      }
    } finally {
      notifyListeners();
    }
  }

  /// Re-roll the welcome-card handle. Cheap — no Firestore write.
  /// Used by the welcome card's "Pick another" button. Avatar may
  /// change too as a side effect (it's bundled with the handle).
  void reroll() {
    if (_profile != null) return; // returning users have no pending
    _pendingHandle = HandleGenerator.generate();
    notifyListeners();
  }

  /// Update ONLY the pending avatar id, preserving the current handle
  /// + display name. Called from the welcome card's avatar picker
  /// when the user taps a different avatar tile — they keep the name
  /// they like and just swap the face.
  void setPendingAvatar(final String avatarId) {
    if (_profile != null) return;
    final GeneratedHandle? current = _pendingHandle;
    if (current == null || current.avatarId == avatarId) return;
    _pendingHandle = GeneratedHandle(
      handle: current.handle,
      displayName: current.displayName,
      avatarId: avatarId,
    );
    notifyListeners();
  }

  /// Generate a fresh pending handle from the user's typed name.
  /// Empty / non-letter input falls back to a random handle (via
  /// [HandleGenerator.fromName]). Preserves the currently picked
  /// avatar so typing doesn't reset the face the user already chose.
  ///
  /// Called from the welcome card as the user types — debounce in
  /// the caller (~250 ms) is recommended to avoid thrashing the
  /// listener on every keystroke.
  void setPendingFromName(final String name) {
    if (_profile != null) return;
    final String? keepAvatar = _pendingHandle?.avatarId;
    _pendingHandle = HandleGenerator.fromName(
      name,
      keepAvatarId: keepAvatar,
    );
    notifyListeners();
  }

  /// Re-roll the *number suffix only* on a name-based pending
  /// handle. Used by the welcome card's "PICK ANOTHER NUMBER" path
  /// when the user has typed a name — they keep the name + avatar
  /// but get a fresh number to dodge a "taken" outcome at confirm
  /// time.
  void rerollNumber() {
    if (_profile != null) return;
    final GeneratedHandle? current = _pendingHandle;
    if (current == null) return;
    // Re-derive from the existing display name (which is the typed
    // name with no digits) so we don't accidentally re-roll the
    // adjective-role pair as a side effect.
    _pendingHandle = HandleGenerator.fromName(
      current.displayName,
      keepAvatarId: current.avatarId,
    );
    notifyListeners();
  }

  /// Persist the pending handle to Firestore and create the user
  /// profile. Tries up to 5 times with re-rolls if the chosen handle
  /// collides with an existing reservation in `handles/`.
  ///
  /// Returns true on success, false if all retries collided (extremely
  /// rare — would require >300k of our handles to be in use).
  Future<bool> confirmProfile() async {
    if (_uid == null) return false;
    if (_profile != null) return true; // already done
    GeneratedHandle current = _pendingHandle ?? HandleGenerator.generate();
    for (int attempt = 0; attempt < 5; attempt++) {
      final bool ok = await _writeProfile(current);
      if (ok) {
        _pendingHandle = null;
        notifyListeners();
        return true;
      }
      // Collision — re-roll and retry.
      current = HandleGenerator.generate();
    }
    if (kDebugMode) debugPrint('UserService: 5 collisions, gave up');
    return false;
  }

  /// Atomically reserves the handle and writes the profile. Returns
  /// false if the handle was already taken (caller should re-roll).
  Future<bool> _writeProfile(final GeneratedHandle pick) async {
    final WriteBatch batch = _db.batch();
    final DocumentReference<Map<String, dynamic>> handleRef = _db
        .collection(_handlesCollection)
        .doc(pick.handle.toLowerCase());
    final DocumentReference<Map<String, dynamic>> userRef =
        _db.collection(_usersCollection).doc(_uid);

    // 1. Try to read the handle — if it exists, someone else has it.
    final DocumentSnapshot<Map<String, dynamic>> existing =
        await handleRef.get();
    if (existing.exists) return false;

    // 2. Reserve the handle + create the profile in one batch. The
    //    `ttl` field on both docs lets Firestore's TTL policy
    //    auto-delete inactive accounts (see [profileTtl]).
    batch.set(handleRef, <String, dynamic>{
      'uid': _uid,
      'created_at': FieldValue.serverTimestamp(),
      'ttl': _futureTtl,
    });

    final Map<String, dynamic> userData = <String, dynamic>{
      'handle': pick.handle,
      'handle_lower': pick.handle.toLowerCase(),
      'display_name': pick.displayName,
      'avatar_id': pick.avatarId,
      'matches_played': 0,
      'matches_won': 0,
      'matches_drawn': 0,
      'goals_scored': 0,
      'goals_conceded': 0,
      'created_at': FieldValue.serverTimestamp(),
      'last_seen_at': FieldValue.serverTimestamp(),
      'ttl': _futureTtl,
    };
    batch.set(userRef, userData);

    try {
      await batch.commit();
      // Re-fetch so the timestamps are populated locally.
      final DocumentSnapshot<Map<String, dynamic>> fresh = await userRef.get();
      _profile = UserProfile.fromMap(_uid!, fresh.data()!);
      if (kDebugMode) {
        debugPrint('UserService: created profile ${pick.handle}');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('UserService: write failed → $e');
      return false;
    }
  }

  /// Push `last_seen_at` AND `ttl` forward on every app launch.
  /// Refreshing `ttl` is what keeps active users alive — Firestore's
  /// TTL service deletes docs whose `ttl` is in the past, so each
  /// launch resets the 30-day countdown. Fire-and-forget; a missed
  /// update just means slightly earlier auto-cleanup.
  ///
  /// Also refreshes the `ttl` on the `handles/{handle_lower}` doc
  /// so the user's reservation outlives their profile (otherwise the
  /// handle could be freed up while the profile still exists).
  Future<void> _touchLastSeen() async {
    if (_uid == null || _profile == null) return;
    try {
      final Timestamp ttl = _futureTtl;
      await _db.collection(_usersCollection).doc(_uid).update(
        <String, dynamic>{
          'last_seen_at': FieldValue.serverTimestamp(),
          'ttl': ttl,
        },
      );
      // Mirror the TTL refresh on the handle reservation so it lives
      // exactly as long as the user. Non-fatal if the doc is missing
      // (legacy accounts created before TTL was added).
      if (_profile!.handleLower.isNotEmpty) {
        await _db
            .collection(_handlesCollection)
            .doc(_profile!.handleLower)
            .set(<String, dynamic>{'ttl': ttl}, SetOptions(merge: true));
      }
    } catch (_) {
      // Swallow — non-fatal.
    }
  }

  /// True when the user is allowed to change their handle right now.
  /// Returns true for users who have never changed it, otherwise
  /// checks against [handleChangeCooldown].
  bool get canChangeHandle {
    final Timestamp? changedAt = _profile?.handleChangedAt;
    if (changedAt == null) return true;
    final DateTime next =
        changedAt.toDate().add(handleChangeCooldown);
    return DateTime.now().isAfter(next);
  }

  /// When the user can next change their handle. Null when no
  /// cooldown is active (i.e. [canChangeHandle] is true).
  DateTime? get nextHandleChangeAt {
    final Timestamp? changedAt = _profile?.handleChangedAt;
    if (changedAt == null) return null;
    final DateTime next =
        changedAt.toDate().add(handleChangeCooldown);
    if (DateTime.now().isAfter(next)) return null;
    return next;
  }

  /// Update the user's avatar in Firestore + local cache. Single-field
  /// write; no uniqueness constraints, so this is fast and never
  /// fails on collision.
  Future<bool> changeAvatar(final String avatarId) async {
    if (_uid == null || _profile == null) return false;
    if (avatarId.isEmpty || avatarId == _profile!.avatarId) return true;
    try {
      await _db.collection(_usersCollection).doc(_uid).update(
        <String, dynamic>{'avatar_id': avatarId},
      );
      _profile = _profile!.copyWith(avatarId: avatarId);
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('UserService: changeAvatar failed → $e');
      return false;
    }
  }

  /// Atomically swap the user's handle: free the old reservation in
  /// `handles/`, claim the new one, and update the profile doc with
  /// the new handle + a fresh `handle_changed_at` timestamp.
  ///
  /// Returns one of:
  ///   • `HandleChangeResult.ok` — success
  ///   • `HandleChangeResult.cooldown` — within the 7-day window
  ///   • `HandleChangeResult.taken` — handle already exists
  ///   • `HandleChangeResult.invalid` — handle empty / same as current
  ///   • `HandleChangeResult.failed` — Firestore error
  Future<HandleChangeResult> changeHandle(final String newHandle) async {
    if (_uid == null || _profile == null) {
      return HandleChangeResult.failed;
    }
    final String trimmed = newHandle.trim();
    if (trimmed.isEmpty || trimmed == _profile!.handle) {
      return HandleChangeResult.invalid;
    }
    if (!canChangeHandle) return HandleChangeResult.cooldown;

    final String newLower = trimmed.toLowerCase();
    final String oldLower = _profile!.handleLower;

    final DocumentReference<Map<String, dynamic>> newRef =
        _db.collection(_handlesCollection).doc(newLower);
    final DocumentReference<Map<String, dynamic>> oldRef =
        _db.collection(_handlesCollection).doc(oldLower);
    final DocumentReference<Map<String, dynamic>> userRef =
        _db.collection(_usersCollection).doc(_uid);

    try {
      final HandleChangeResult result = await _db.runTransaction<
          HandleChangeResult>((final Transaction tx) async {
        final DocumentSnapshot<Map<String, dynamic>> existing =
            await tx.get(newRef);
        if (existing.exists) {
          // Allow re-claiming our own (case-only change), otherwise
          // someone else owns it.
          final String? existingUid = existing.data()?['uid'] as String?;
          if (existingUid != _uid) return HandleChangeResult.taken;
        }
        final Timestamp ttl = _futureTtl;
        // Reserve the new handle.
        tx.set(newRef, <String, dynamic>{
          'uid': _uid,
          'created_at': FieldValue.serverTimestamp(),
          'ttl': ttl,
        });
        // Free the old reservation (only if different from new).
        if (oldLower != newLower && oldLower.isNotEmpty) {
          tx.delete(oldRef);
        }
        // Update the profile.
        tx.update(userRef, <String, dynamic>{
          'handle': trimmed,
          'handle_lower': newLower,
          'display_name': _humanReadable(trimmed),
          'handle_changed_at': FieldValue.serverTimestamp(),
        });
        return HandleChangeResult.ok;
      });

      if (result == HandleChangeResult.ok) {
        // Re-fetch so timestamps populate locally.
        final DocumentSnapshot<Map<String, dynamic>> fresh =
            await userRef.get();
        if (fresh.data() != null) {
          _profile = UserProfile.fromMap(_uid!, fresh.data()!);
        }
        notifyListeners();
      }
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('UserService: changeHandle failed → $e');
      return HandleChangeResult.failed;
    }
  }

  /// Strip the trailing digits from a handle to produce a human-
  /// readable display name (mirrors [HandleGenerator]'s convention
  /// where "BraveTiger47" → "Brave Tiger"). Best-effort — falls back
  /// to the raw handle if no transformation is obvious.
  static String _humanReadable(final String handle) {
    // Remove trailing digits.
    final RegExp trailingDigits = RegExp(r'\d+$');
    String stripped = handle.replaceAll(trailingDigits, '');
    if (stripped.isEmpty) stripped = handle;
    // Insert spaces before internal capitals (CamelCase → "Camel Case").
    final RegExp camelBoundary = RegExp(r'(?<=[a-z])(?=[A-Z])');
    return stripped.replaceAll(camelBoundary, ' ');
  }

  /// Quickly check whether a candidate handle is currently free.
  /// Returns true if the handle is available, false if taken.
  /// Used by the change-handle UI to debounce-validate input as the
  /// user types.
  Future<bool> isHandleAvailable(final String candidate) async {
    final String trimmed = candidate.trim();
    if (trimmed.isEmpty) return false;
    if (_profile != null &&
        trimmed.toLowerCase() == _profile!.handleLower) {
      // The user's current handle "isn't taken" from their POV.
      return true;
    }
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _db
          .collection(_handlesCollection)
          .doc(trimmed.toLowerCase())
          .get();
      return !snap.exists;
    } catch (_) {
      return false;
    }
  }

  /// Bump the user's match-end stats atomically. Called from
  /// game-over handling. Server-side `FieldValue.increment` ensures
  /// concurrent matches (rare in single-device play, common in online
  /// play) don't lose updates.
  Future<void> bumpStats({
    required final bool won,
    required final bool drawn,
    required final int goalsScored,
    required final int goalsConceded,
  }) async {
    if (_uid == null || _profile == null) return;
    try {
      await _db.collection(_usersCollection).doc(_uid).update(
        <String, dynamic>{
          'matches_played': FieldValue.increment(1),
          if (won) 'matches_won': FieldValue.increment(1),
          if (drawn) 'matches_drawn': FieldValue.increment(1),
          'goals_scored': FieldValue.increment(goalsScored),
          'goals_conceded': FieldValue.increment(goalsConceded),
        },
      );
      // Optimistically reflect locally so Settings stats refresh
      // without a re-fetch.
      _profile = _profile!.copyWith(
        matchesPlayed: _profile!.matchesPlayed + 1,
        matchesWon: _profile!.matchesWon + (won ? 1 : 0),
        matchesDrawn: _profile!.matchesDrawn + (drawn ? 1 : 0),
        goalsScored: _profile!.goalsScored + goalsScored,
        goalsConceded: _profile!.goalsConceded + goalsConceded,
      );
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('UserService: bumpStats failed → $e');
    }
  }
}

/// Outcome of [UserService.changeHandle]. The profile screen maps
/// these to user-facing snackbars / inline errors.
enum HandleChangeResult {
  /// Handle successfully reserved + profile updated.
  ok,

  /// Within the [UserService.handleChangeCooldown] window. UI should
  /// show "Next change in Xd Yh".
  cooldown,

  /// Handle is already reserved by another user.
  taken,

  /// Empty / unchanged / fails client-side validation rules.
  invalid,

  /// Firestore write failed (network, permissions, etc.). UI should
  /// show a generic "Try again" message.
  failed,
}

