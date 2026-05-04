import 'package:cloud_firestore/cloud_firestore.dart';

/// Persistent per-install user identity. One document per Firebase
/// Anonymous Auth `uid` in the `users/` Firestore collection.
///
/// Created on first launch by [UserService.loadOrCreate] and updated
/// thereafter via stat-bump helpers + the Settings → Edit Profile
/// flow. Auto-deleted by Firebase Auth's 30-day inactivity policy +
/// our `onUserDeleted` Cloud Function (see deployment notes).
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.handle,
    required this.handleLower,
    required this.displayName,
    required this.avatarId,
    required this.matchesPlayed,
    required this.matchesWon,
    required this.matchesDrawn,
    required this.goalsScored,
    required this.goalsConceded,
    this.createdAt,
    this.lastSeenAt,
    this.handleChangedAt,
  });

  final String uid;
  final String handle;
  /// Lowercased copy of [handle] used as the doc id in the
  /// `handles/` uniqueness collection. Lets us do
  /// case-insensitive collision checks ("BraveTiger47" and
  /// "BRAVETIGER47" can't both exist).
  final String handleLower;
  /// Human-readable form — handle without the trailing number.
  final String displayName;
  /// Maps to [HandleGenerator.avatarEmoji].
  final String avatarId;

  // ── Stats (incremented atomically via FieldValue.increment) ────
  final int matchesPlayed;
  final int matchesWon;
  final int matchesDrawn;
  final int goalsScored;
  final int goalsConceded;

  final Timestamp? createdAt;
  final Timestamp? lastSeenAt;
  /// When the user last changed their handle. Used to enforce the
  /// 7-day rate limit in Settings → Edit Profile.
  final Timestamp? handleChangedAt;

  /// Convenience: matches lost = played − won − drawn.
  int get matchesLost => matchesPlayed - matchesWon - matchesDrawn;

  factory UserProfile.fromMap(
    final String uid,
    final Map<String, dynamic> data,
  ) {
    return UserProfile(
      uid: uid,
      handle: (data['handle'] as String?) ?? '',
      handleLower: (data['handle_lower'] as String?) ?? '',
      displayName: (data['display_name'] as String?) ?? '',
      avatarId: (data['avatar_id'] as String?) ?? 'Tiger',
      matchesPlayed: (data['matches_played'] as num?)?.toInt() ?? 0,
      matchesWon: (data['matches_won'] as num?)?.toInt() ?? 0,
      matchesDrawn: (data['matches_drawn'] as num?)?.toInt() ?? 0,
      goalsScored: (data['goals_scored'] as num?)?.toInt() ?? 0,
      goalsConceded: (data['goals_conceded'] as num?)?.toInt() ?? 0,
      createdAt: data['created_at'] as Timestamp?,
      lastSeenAt: data['last_seen_at'] as Timestamp?,
      handleChangedAt: data['handle_changed_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'handle': handle,
        'handle_lower': handleLower,
        'display_name': displayName,
        'avatar_id': avatarId,
        'matches_played': matchesPlayed,
        'matches_won': matchesWon,
        'matches_drawn': matchesDrawn,
        'goals_scored': goalsScored,
        'goals_conceded': goalsConceded,
        if (createdAt != null) 'created_at': createdAt,
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
        if (handleChangedAt != null) 'handle_changed_at': handleChangedAt,
      };

  UserProfile copyWith({
    final String? handle,
    final String? handleLower,
    final String? displayName,
    final String? avatarId,
    final int? matchesPlayed,
    final int? matchesWon,
    final int? matchesDrawn,
    final int? goalsScored,
    final int? goalsConceded,
    final Timestamp? lastSeenAt,
    final Timestamp? handleChangedAt,
  }) =>
      UserProfile(
        uid: uid,
        handle: handle ?? this.handle,
        handleLower: handleLower ?? this.handleLower,
        displayName: displayName ?? this.displayName,
        avatarId: avatarId ?? this.avatarId,
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        matchesWon: matchesWon ?? this.matchesWon,
        matchesDrawn: matchesDrawn ?? this.matchesDrawn,
        goalsScored: goalsScored ?? this.goalsScored,
        goalsConceded: goalsConceded ?? this.goalsConceded,
        createdAt: createdAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        handleChangedAt: handleChangedAt ?? this.handleChangedAt,
      );
}
