/// Snapshot of a player's identity at the moment they joined a match.
///
/// We deliberately COPY (not reference) handle + avatar into the match
/// doc instead of looking them up via uid each frame. This way:
///   • Opponents render immediately without a second Firestore read
///   • If a player changes their handle mid-match (or the underlying
///     `users/{uid}` doc is deleted via TTL), their in-game name
///     stays stable until the match ends
///   • Match docs are self-contained — useful for replay / history
class MatchPlayer {
  const MatchPlayer({
    required this.uid,
    required this.handle,
    required this.displayName,
    required this.avatarId,
  });

  final String uid;
  final String handle;
  final String displayName;
  final String avatarId;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'uid': uid,
        'handle': handle,
        'display_name': displayName,
        'avatar_id': avatarId,
      };

  factory MatchPlayer.fromMap(final Map<String, dynamic> data) =>
      MatchPlayer(
        uid: (data['uid'] as String?) ?? '',
        handle: (data['handle'] as String?) ?? '',
        displayName: (data['display_name'] as String?) ?? '',
        avatarId: (data['avatar_id'] as String?) ?? 'tiger',
      );
}
